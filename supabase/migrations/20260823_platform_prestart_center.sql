begin;

create or replace function public.get_platform_prestart_center_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'ready',(select count(*) from public.service_requests r join lateral (select * from public.implementation_plans p where p.request_no=r.request_no and p.status<>'superseded' order by p.version desc limit 1) p on true where r.status not in ('closed','completed','cancelled','archived') and p.prestart_ready and r.assigned_worker_phone is not null and r.accepted_at is not null and r.arrived_at is not null and r.prework_confirmed_at is not null and coalesce((r.prework_agreement->>'site_conditions_confirmed')::boolean,false) and coalesce((r.prework_agreement->>'scope_quality_time_confirmed')::boolean,false) and r.prework_agreement->>'prestart_photo_path' is not null),
      'blocked',(select count(*) from public.service_requests r join lateral (select * from public.implementation_plans p where p.request_no=r.request_no and p.status<>'superseded' order by p.version desc limit 1) p on true where r.status in ('assigned','accepted','arrived') and not (p.prestart_ready and r.accepted_at is not null and r.arrived_at is not null and r.prework_confirmed_at is not null)),
      'legacy_started_without_gate',(select count(*) from public.service_requests r join lateral (select * from public.implementation_plans p where p.request_no=r.request_no and p.status<>'superseded' order by p.version desc limit 1) p on true where r.status in ('working','in_progress','milestone_submitted','milestone_customer_approved','awaiting_final_acceptance') and not p.prestart_ready)
    ),
    'orders',coalesce((select jsonb_agg(jsonb_build_object(
      'request_no',r.request_no,'service_type',r.service_type,'order_status',r.status,'worker',r.assigned_worker,
      'plan_version',p.version,'plan_approved',p.platform_approval_status='approved',
      'customer_confirmed',p.status='customer_confirmed' or p.customer_confirmed_at is not null,
      'plan_ready',p.prestart_ready,'worker_accepted',r.accepted_at is not null,'arrival_confirmed',r.arrived_at is not null,
      'prework_confirmed',r.prework_confirmed_at is not null,
      'site_conditions',coalesce((r.prework_agreement->>'site_conditions_confirmed')::boolean,false),
      'scope_quality_time',coalesce((r.prework_agreement->>'scope_quality_time_confirmed')::boolean,false),
      'photo_evidence',r.prework_agreement->>'prestart_photo_path' is not null,
      'worker_qualified',exists(select 1 from public.service_workers w where w.phone=r.assigned_worker_phone and w.status='active' and w.verification_status='verified' and w.credit_score>=60),
      'sections_complete',(select count(distinct s.section_code)=7 from public.plan_sections s where s.plan_id=p.id and s.section_code in ('man','machine','material','method','environment','schedule','quality') and s.status in ('completed','approved') and s.content<>'{}'::jsonb),
      'legacy_gate_violation',r.status in ('working','in_progress','milestone_submitted','milestone_customer_approved','awaiting_final_acceptance') and not p.prestart_ready
    ) order by r.updated_at desc) from public.service_requests r join lateral (select * from public.implementation_plans p where p.request_no=r.request_no and p.status<>'superseded' order by p.version desc limit 1) p on true where r.status not in ('closed','completed','cancelled','archived')),'[]'::jsonb)
  );
end;$function$;

revoke all on function public.get_platform_prestart_center_with_token(text) from public,anon,authenticated;
grant execute on function public.get_platform_prestart_center_with_token(text) to anon,authenticated,service_role;

commit;
