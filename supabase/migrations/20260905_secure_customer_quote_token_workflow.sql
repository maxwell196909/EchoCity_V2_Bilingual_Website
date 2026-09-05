create or replace function public.get_customer_quote_with_token(p_request_no text, p_token text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_no text:=upper(trim(p_request_no));
  r public.service_requests;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_no,'customer',p_token) then
    raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID';
  end if;
  select * into r from public.service_requests where request_no=v_no and quote_amount is not null;
  if not found then raise exception 'QUOTE_NOT_FOUND'; end if;
  return jsonb_build_object(
    'request_no',r.request_no,'service_type',r.service_type,'description',r.description,
    'service_date',r.service_date,'start_time',r.start_time,'workers',r.workers,'address',r.address,
    'status',r.status,'quote_amount',r.quote_amount,'quote_note',r.quote_note,'quote_confirmed',r.quote_confirmed
  );
end;
$function$;

create or replace function public.submit_customer_quote_decision_with_token(p_request_no text,p_token text,p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_no text:=upper(trim(p_request_no));
  v_request public.service_requests%rowtype;
  v_from_status text;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_no,'customer',p_token) then
    raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID';
  end if;
  select status into v_from_status from public.service_requests where request_no=v_no for update;
  update public.service_requests
     set status=case when p_accept then 'quote_confirmed' else 'quote_declined' end,
         quote_confirmed=p_accept,
         current_actor='platform',
         next_action=case when p_accept then 'assign_worker' else 'prepare_quote' end,
         updated_at=now()
   where request_no=v_no
     and quote_amount is not null
     and status in ('quoted','quote_confirmed','quote_declined')
  returning * into v_request;
  if not found then raise exception 'QUOTE_NOT_FOUND_OR_NOT_ACTIONABLE'; end if;
  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence)
  values(v_request.request_no,'quote_decision',case when p_accept then 'customer_accepted_quote' else 'customer_declined_quote' end,
    'customer',v_from_status,v_request.status,
    case when p_accept then '客户通过专用链接确认报价，等待平台派工' else '客户通过专用链接暂不接受报价，退回平台处理' end,
    jsonb_build_object('accepted',p_accept,'quote_amount',v_request.quote_amount,'auth','customer_token'));
  return jsonb_build_object('request_no',v_request.request_no,'service_type',v_request.service_type,'description',v_request.description,
    'service_date',v_request.service_date,'start_time',v_request.start_time,'workers',v_request.workers,'address',v_request.address,
    'status',v_request.status,'quote_amount',v_request.quote_amount,'quote_note',v_request.quote_note,
    'quote_confirmed',v_request.quote_confirmed,'current_actor',v_request.current_actor,'next_action',v_request.next_action);
end;
$function$;

create or replace function public.issue_customer_quote_link_with_token(p_platform_token text,p_request_no text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_no text:=upper(trim(p_request_no));
  v_token text;
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;
  if not exists(select 1 from public.service_requests r where r.request_no=v_no and r.quote_amount is not null and r.status in ('quoted','quote_confirmed','quote_declined')) then
    raise exception 'QUOTE_NOT_READY';
  end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at,revoked_at)
  values(v_no,'customer',encode(extensions.digest(v_token,'sha256'),'hex'),now()+interval '7 days',null)
  on conflict(request_no,role) do update
    set token_hash=excluded.token_hash,expires_at=excluded.expires_at,revoked_at=null;
  insert into public.task_events(request_no,event_type,action,actor_role,to_status,note,evidence)
  values(v_no,'access','issue_customer_quote_link','platform','quoted','平台生成客户专用报价链接',jsonb_build_object('expires_hours',168));
  return jsonb_build_object('request_no',v_no,'customer_token',v_token,'expires_at',now()+interval '7 days');
end;
$function$;
