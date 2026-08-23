begin;
create or replace function public.reissue_worker_link_with_platform_token(p_request_no text,p_platform_token text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_token text; v_no text;
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select request_no into v_no from public.service_requests where request_no=upper(trim(p_request_no)) and status in ('assigned','accepted','arrived','in_progress');
  if v_no is null then raise exception 'ACTIVE_TASK_NOT_FOUND'; end if;
  update public.task_access_tokens set revoked_at=now() where request_no=v_no and role='worker' and revoked_at is null;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at) values(v_no,'worker',encode(extensions.digest(v_token,'sha256'),'hex'),now()+interval '30 days');
  return jsonb_build_object('request_no',v_no,'worker_token',v_token);
end;$function$;
revoke all on function public.reissue_worker_link_with_platform_token(text,text) from public,anon,authenticated;
grant execute on function public.reissue_worker_link_with_platform_token(text,text) to anon,authenticated,service_role;
commit;

begin;
create or replace function public.set_worker_link_with_platform_token(p_request_no text,p_platform_token text,p_new_token text)
returns boolean language plpgsql security definer set search_path='' as $function$
declare v_no text;
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if p_new_token is null or length(p_new_token)<>64 then raise exception 'INVALID_NEW_WORKER_TOKEN'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select request_no into v_no from public.service_requests where request_no=upper(trim(p_request_no)) and status in ('assigned','accepted','arrived','in_progress');
  if v_no is null then raise exception 'ACTIVE_TASK_NOT_FOUND'; end if;
  update public.task_access_tokens set revoked_at=now() where request_no=v_no and role='worker' and revoked_at is null;
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at) values(v_no,'worker',encode(extensions.digest(p_new_token,'sha256'),'hex'),now()+interval '30 days');
  return true;
end;$function$;
revoke all on function public.set_worker_link_with_platform_token(text,text,text) from public,anon,authenticated;
grant execute on function public.set_worker_link_with_platform_token(text,text,text) to anon,authenticated,service_role;
commit;
