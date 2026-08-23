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
  values(v_request.request_no,v_version,'approved',jsonb_build_object('task_scope',coalesce(v_request.worker_task_scope,v_request.description),'assigned_worker',v_request.assigned_worker,'planned_start',v_request.assigned_start_time),now(),now(),'approved',now(),'平台重新签发，等待客户确认',false);
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at,revoked_at)
  values(v_request.request_no,'customer',encode(extensions.digest(v_token,'sha256'),'hex'),now()+interval '30 days',null)
  on conflict(request_no,role) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,revoked_at=null;
  return jsonb_build_object('request_no',v_request.request_no,'customer_token',v_token,'plan_version',v_version);
end;$function$;

revoke all on function public.prepare_assignment_plan_with_token(text,text) from public,anon,authenticated;
grant execute on function public.prepare_assignment_plan_with_token(text,text) to anon,authenticated,service_role;

commit;
