create or replace function public.get_platform_cross_module_matrix_with_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare result jsonb;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  with matrix as (
    select r.request_no,r.service_type,r.status as order_status,r.current_actor,r.next_action,r.updated_at,
      case when r.assigned_worker_phone is null then 'unassigned' when sw.id is null then 'profile_missing' when sw.verification_status='qualified' then 'qualified' else coalesce(sw.verification_status,'pending') end worker_status,
      case when p.id is null then 'missing' when p.customer_confirmed_at is not null then 'customer_confirmed' when p.platform_approval_status='approved' then 'platform_approved' else coalesce(p.status,'pending') end plan_status,
      case when p.id is null then 'not_ready' when p.prestart_ready then 'ready' else 'blocked' end prestart_status,
      case when r.work_completed_at is not null or r.status in ('completed','closed') then 'completed' when r.work_started_at is not null then 'in_progress' when r.assigned_worker_phone is not null then 'not_started' else 'not_applicable' end work_status,
      (select count(*) from public.work_records wr where wr.request_no=r.request_no) work_record_count,
      case when r.final_acceptance_status='accepted' then 'accepted' when r.status='awaiting_final_acceptance' then 'awaiting_customer' when r.status in ('rework','disputed') then r.status else 'not_ready' end quality_status,
      coalesce(os.status,'not_created') settlement_status,coalesce(w.status,'not_created') warranty_status,
      (select count(*) from public.after_sales_cases c where c.request_no=r.request_no and c.status not in ('closed','rejected')) open_after_sales,
      (select count(*) from public.after_sales_cases c where c.request_no=r.request_no and c.status not in ('closed','rejected') and c.due_at<now()) overdue_after_sales,
      (select count(*) from public.platform_incidents i where i.request_no=r.request_no and i.status<>'resolved') open_incidents,
      case
        when (select count(*) from public.platform_incidents i where i.request_no=r.request_no and i.status<>'resolved')>0 then 'incident'
        when (select count(*) from public.after_sales_cases c where c.request_no=r.request_no and c.status not in ('closed','rejected') and c.due_at<now())>0 then 'overdue'
        when r.assigned_worker_phone is not null and coalesce(sw.verification_status,'pending')<>'qualified' and r.status not in ('closed','completed') then 'qualification_block'
        when r.work_started_at is not null and r.status not in ('closed','completed','awaiting_final_acceptance') and coalesce(p.prestart_ready,false)=false then 'gate_warning'
        else 'connected' end health
    from public.service_requests r
    left join public.service_workers sw on regexp_replace(sw.phone,'\D','','g')=regexp_replace(coalesce(r.assigned_worker_phone,''),'\D','','g')
    left join lateral (select * from public.implementation_plans x where x.request_no=r.request_no order by x.version desc limit 1) p on true
    left join lateral (select * from public.order_settlements x where x.request_no=r.request_no order by x.updated_at desc limit 1) os on true
    left join public.warranty_records w on w.request_no=r.request_no
  )
  select jsonb_build_object('summary',jsonb_build_object('orders',count(*),'connected',count(*) filter(where health='connected'),'attention',count(*) filter(where health<>'connected'),'open_after_sales',coalesce(sum(open_after_sales),0),'open_incidents',coalesce(sum(open_incidents),0)),
    'orders',coalesce(jsonb_agg(jsonb_build_object('request_no',request_no,'service_type',service_type,'order_status',order_status,'current_actor',current_actor,'next_action',next_action,'worker_status',worker_status,'plan_status',plan_status,'prestart_status',prestart_status,'work_status',work_status,'work_record_count',work_record_count,'quality_status',quality_status,'settlement_status',settlement_status,'warranty_status',warranty_status,'open_after_sales',open_after_sales,'overdue_after_sales',overdue_after_sales,'open_incidents',open_incidents,'health',health,'updated_at',updated_at) order by case when health='connected' then 1 else 0 end,updated_at desc),'[]'::jsonb)) into result from matrix;
  return result;
end;$$;
revoke all on function public.get_platform_cross_module_matrix_with_token(text) from public;
grant execute on function public.get_platform_cross_module_matrix_with_token(text) to anon,authenticated,service_role;
