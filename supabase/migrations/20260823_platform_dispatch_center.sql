begin;

create or replace function public.get_platform_dispatch_center_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'ready_to_assign',(select count(*) from public.service_requests where status in ('confirmed','quote_confirmed')),
      'awaiting_worker',(select count(*) from public.service_requests where status='assigned'),
      'active_tasks',(select count(*) from public.service_requests where status in ('accepted','arrived','working','in_progress','milestone_submitted','milestone_customer_approved')),
      'plan_review',(select count(*) from public.implementation_plans where status in ('submitted','under_review') or platform_approval_status in ('pending','under_review')),
      'qualified_workers',(select count(*) from public.service_workers where status='active' and verification_status='verified' and availability_status='available' and credit_score>=60),
      'worker_verification_pending',(select count(*) from public.service_workers where verification_status in ('unverified','pending'))
    ),
    'tasks',coalesce((select jsonb_agg(jsonb_build_object(
      'request_no',r.request_no,'service_type',r.service_type,'status',r.status,'risk_level',r.risk_level,
      'current_actor',r.current_actor,'next_action',r.next_action,'assigned_worker',r.assigned_worker,
      'assigned_worker_phone',r.assigned_worker_phone,'assigned_start_time',r.assigned_start_time,
      'updated_at',r.updated_at,'hours_waiting',floor(extract(epoch from(now()-r.updated_at))/3600),
      'queue',case when r.status in ('confirmed','quote_confirmed') then 'ready_to_assign' when r.status='assigned' then 'awaiting_worker' when r.status in ('accepted','arrived','working','in_progress','milestone_submitted','milestone_customer_approved') then 'active' else 'follow_up' end
    ) order by case when r.status in ('confirmed','quote_confirmed') then 1 when r.status='assigned' then 2 else 3 end,r.updated_at)
    from public.service_requests r where r.status not in ('closed','cancelled','archived')),'[]'::jsonb),
    'qualified_candidates',coalesce((select jsonb_agg(jsonb_build_object(
      'id',w.id,'full_name',w.full_name,'phone',w.phone,'skills',w.skills,'credit_score',w.credit_score,
      'completed_orders',w.completed_orders,'availability_status',w.availability_status
    ) order by w.credit_score desc,w.completed_orders desc)
    from public.service_workers w where w.status='active' and w.verification_status='verified' and w.availability_status='available' and w.credit_score>=60),'[]'::jsonb)
  );
end;$function$;

revoke all on function public.get_platform_dispatch_center_with_token(text) from public,anon,authenticated;
grant execute on function public.get_platform_dispatch_center_with_token(text) to anon,authenticated,service_role;

commit;
