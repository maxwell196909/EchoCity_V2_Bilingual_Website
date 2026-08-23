begin;

create or replace function public.prepare_assignment_plan_with_token(p_request_no text, p_platform_token text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_request public.service_requests%rowtype; v_token text; v_version integer;
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select * into v_request from public.service_requests r where r.request_no=upper(trim(p_request_no)) and r.status in ('assigned','accepted','arrived');
  if not found then raise exception 'ASSIGNED_REQUEST_NOT_FOUND'; end if;
  select coalesce(max(version),0)+1 into v_version from public.implementation_plans p where p.request_no=v_request.request_no;
  insert into public.implementation_plans(request_no,version,status,content,submitted_at,approved_at,platform_approval_status,platform_approved_at,approval_note,prestart_ready)
  values(v_request.request_no,v_version,'approved',jsonb_build_object('task_scope',coalesce(v_request.worker_task_scope,v_request.description),'assigned_worker',v_request.assigned_worker,'planned_start',v_request.assigned_start_time),now(),now(),'approved',now(),'平台派工时批准，等待客户确认',false);
  update public.task_access_tokens set revoked_at=now() where request_no=v_request.request_no and role='customer' and revoked_at is null;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at) values(v_request.request_no,'customer',encode(extensions.digest(v_token,'sha256'),'hex'),now()+interval '30 days');
  return jsonb_build_object('request_no',v_request.request_no,'customer_token',v_token,'plan_version',v_version);
end;$function$;

create or replace function public.confirm_assignment_plan_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_plan public.implementation_plans%rowtype;
begin
  if not public.validate_task_access_token(upper(trim(p_request_no)),'customer',p_token) then raise exception 'TASK_LINK_EXPIRED_OR_INVALID'; end if;
  update public.implementation_plans p set status='customer_confirmed',customer_confirmed_at=coalesce(p.customer_confirmed_at,now()),prestart_ready=true,updated_at=now()
  where p.id=(select p2.id from public.implementation_plans p2 where p2.request_no=upper(trim(p_request_no)) and p2.platform_approval_status='approved' order by p2.version desc limit 1)
  returning * into v_plan;
  if not found then raise exception 'APPROVED_PLAN_NOT_FOUND'; end if;
  return jsonb_build_object('request_no',v_plan.request_no,'version',v_plan.version,'status',v_plan.status,'customer_confirmed_at',v_plan.customer_confirmed_at);
end;$function$;

revoke all on function public.prepare_assignment_plan_with_token(text,text) from public,anon,authenticated;
revoke all on function public.confirm_assignment_plan_with_token(text,text) from public,anon,authenticated;
grant execute on function public.prepare_assignment_plan_with_token(text,text) to anon,authenticated,service_role;
grant execute on function public.confirm_assignment_plan_with_token(text,text) to anon,authenticated,service_role;
commit;
