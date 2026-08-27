-- Keep quote workflow status, role handoff and audit events in sync.

create or replace function public.save_platform_quote_with_token(
  p_request_no text,
  p_token text,
  p_quote_amount numeric,
  p_quote_note text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_from_status text;
begin
  if p_token is null or length(p_token) < 64 or length(p_token) > 128 then
    raise exception 'INVALID_PLATFORM_LINK';
  end if;
  if not exists (
    select 1
    from private.platform_dashboard_tokens access_token
    where access_token.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and access_token.revoked_at is null
      and access_token.expires_at > now()
  ) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;
  if p_quote_amount is null or p_quote_amount < 0 or p_quote_amount > 1000000000 then
    raise exception 'INVALID_QUOTE_AMOUNT';
  end if;
  if length(coalesce(p_quote_note, '')) > 5000 then
    raise exception 'QUOTE_NOTE_TOO_LONG';
  end if;

  select request.status into v_from_status
  from public.service_requests request
  where request.request_no = upper(trim(p_request_no))
  for update;

  update public.service_requests request
  set quote_amount = p_quote_amount,
      quote_note = nullif(trim(p_quote_note), ''),
      status = 'quoted',
      quote_confirmed = false,
      current_actor = 'customer',
      next_action = 'confirm_quote',
      updated_at = now()
  where request.request_no = upper(trim(p_request_no))
    and request.status in ('submitted', 'reviewed', 'quoted', 'quote_declined')
  returning * into v_request;

  if not found then
    raise exception 'REQUEST_NOT_QUOTABLE';
  end if;

  insert into public.task_events(
    request_no, event_type, action, actor_role,
    from_status, to_status, note, evidence
  ) values (
    v_request.request_no, 'quote', 'platform_saved_quote', 'platform',
    v_from_status, 'quoted', '平台已提交报价，等待客户确认',
    jsonb_build_object('quote_amount', v_request.quote_amount)
  );

  return jsonb_build_object(
    'request_no', v_request.request_no,
    'quote_amount', v_request.quote_amount,
    'quote_note', v_request.quote_note,
    'status', v_request.status,
    'current_actor', v_request.current_actor,
    'next_action', v_request.next_action,
    'updated_at', v_request.updated_at
  );
end;
$function$;

create or replace function public.submit_customer_quote_decision(
  p_request_no text,
  p_customer_phone text,
  p_accept boolean
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_from_status text;
begin
  select request.status into v_from_status
  from public.service_requests request
  where request.request_no = upper(trim(p_request_no))
  for update;

  update public.service_requests request
  set status = case when p_accept then 'quote_confirmed' else 'quote_declined' end,
      quote_confirmed = p_accept,
      current_actor = 'platform',
      next_action = case when p_accept then 'assign_worker' else 'prepare_quote' end,
      updated_at = now()
  where request.request_no = upper(trim(p_request_no))
    and regexp_replace(coalesce(request.customer_phone, ''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g')
    and length(regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g'))
        between 7 and 20
    and request.quote_amount is not null
    and request.status in ('quoted', 'quote_confirmed', 'quote_declined')
  returning * into v_request;

  if not found then
    raise exception 'QUOTE_NOT_FOUND_OR_NOT_ACTIONABLE';
  end if;

  insert into public.task_events(
    request_no, event_type, action, actor_role,
    from_status, to_status, note, evidence
  ) values (
    v_request.request_no,
    'quote_decision',
    case when p_accept then 'customer_accepted_quote' else 'customer_declined_quote' end,
    'customer',
    v_from_status,
    v_request.status,
    case
      when p_accept then '客户已确认报价，等待平台派工'
      else '客户暂不接受报价，退回平台处理'
    end,
    jsonb_build_object('accepted', p_accept, 'quote_amount', v_request.quote_amount)
  );

  return jsonb_build_object(
    'request_no', v_request.request_no,
    'service_type', v_request.service_type,
    'description', v_request.description,
    'service_date', v_request.service_date,
    'start_time', v_request.start_time,
    'workers', v_request.workers,
    'address', v_request.address,
    'status', v_request.status,
    'quote_amount', v_request.quote_amount,
    'quote_note', v_request.quote_note,
    'quote_confirmed', v_request.quote_confirmed,
    'current_actor', v_request.current_actor,
    'next_action', v_request.next_action
  );
end;
$function$;

revoke all on function public.save_platform_quote_with_token(text, text, numeric, text) from public;
grant execute on function public.save_platform_quote_with_token(text, text, numeric, text) to anon, authenticated;
revoke all on function public.submit_customer_quote_decision(text, text, boolean) from public;
grant execute on function public.submit_customer_quote_decision(text, text, boolean) to anon, authenticated;
