-- Rotate the single worker link safely and audit assignment/worker transitions.

create or replace function public.save_platform_assignment_with_token(
  p_request_no text, p_platform_token text, p_worker_name text, p_worker_phone text,
  p_meeting_date date, p_meeting_time time without time zone, p_worker_pay numeric,
  p_task_scope text, p_site_manager text, p_site_manager_phone text, p_assignment_notes text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_worker_token text;
  v_from_status text;
begin
  if p_platform_token is null or length(p_platform_token) < 64 or length(p_platform_token) > 128 then
    raise exception 'INVALID_PLATFORM_LINK';
  end if;
  if not exists (
    select 1 from private.platform_dashboard_tokens access_token
    where access_token.token_hash = encode(extensions.digest(p_platform_token, 'sha256'), 'hex')
      and access_token.revoked_at is null and access_token.expires_at > now()
  ) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;
  if length(trim(coalesce(p_worker_name, ''))) not between 1 and 120 then raise exception 'INVALID_WORKER_NAME'; end if;
  if length(regexp_replace(coalesce(p_worker_phone, ''), '[^0-9]', '', 'g')) not between 7 and 20 then raise exception 'INVALID_WORKER_PHONE'; end if;
  if p_worker_pay is null or p_worker_pay < 0 or p_worker_pay > 100000000 then raise exception 'INVALID_WORKER_PAY'; end if;
  if length(coalesce(p_task_scope, '')) > 5000 or length(coalesce(p_assignment_notes, '')) > 5000 then
    raise exception 'ASSIGNMENT_TEXT_TOO_LONG';
  end if;

  select request.status into v_from_status
  from public.service_requests request
  where request.request_no = upper(trim(p_request_no))
  for update;

  update public.service_requests request
  set assigned_worker = trim(p_worker_name),
      assigned_worker_phone = trim(p_worker_phone),
      start_time = p_meeting_time,
      assigned_start_time = case
        when p_meeting_date is not null and p_meeting_time is not null
        then (p_meeting_date + p_meeting_time) at time zone 'Asia/Shanghai'
        else null
      end,
      worker_pay = p_worker_pay,
      worker_task_scope = nullif(trim(p_task_scope), ''),
      prework_agreement = coalesce(request.prework_agreement, '{}'::jsonb) || jsonb_build_object(
        'site_manager', nullif(trim(p_site_manager), ''),
        'site_manager_phone', nullif(trim(p_site_manager_phone), ''),
        'assignment_notes', nullif(trim(p_assignment_notes), '')
      ),
      current_actor = 'worker',
      next_action = 'accept_task',
      status = 'assigned',
      updated_at = now()
  where request.request_no = upper(trim(p_request_no))
    and request.status in ('quote_confirmed', 'confirmed', 'assigned')
  returning * into v_request;

  if not found then raise exception 'REQUEST_NOT_ASSIGNABLE'; end if;

  v_worker_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.task_access_tokens(request_no, role, token_hash, expires_at, revoked_at)
  values(
    v_request.request_no,
    'worker',
    encode(extensions.digest(v_worker_token, 'sha256'), 'hex'),
    now() + interval '30 days',
    null
  )
  on conflict(request_no, role) do update
  set token_hash = excluded.token_hash,
      expires_at = excluded.expires_at,
      revoked_at = null,
      created_at = now();

  insert into public.task_events(
    request_no, event_type, action, actor_role,
    from_status, to_status, note, evidence
  ) values (
    v_request.request_no,
    'assignment',
    'platform_assigned_worker',
    'platform',
    v_from_status,
    'assigned',
    '平台已派工，等待服务方接单',
    jsonb_build_object(
      'assigned_worker', v_request.assigned_worker,
      'assigned_start_time', v_request.assigned_start_time
    )
  );

  return jsonb_build_object(
    'request_no', v_request.request_no,
    'status', v_request.status,
    'current_actor', v_request.current_actor,
    'next_action', v_request.next_action,
    'assigned_worker', v_request.assigned_worker,
    'assigned_worker_phone', v_request.assigned_worker_phone,
    'worker_token', v_worker_token
  );
end;
$function$;

create or replace function public.transition_worker_task_with_token(
  p_request_no text,
  p_token text,
  p_action text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_from_status text;
  v_action text;
  v_note text;
begin
  if p_token is null or length(p_token) < 32 or length(p_token) > 128 then
    raise exception 'INVALID_TASK_LINK';
  end if;
  if not exists (
    select 1 from public.task_access_tokens access_token
    where access_token.request_no = upper(trim(p_request_no))
      and access_token.role = 'worker'
      and access_token.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and access_token.revoked_at is null
      and access_token.expires_at > now()
  ) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  select request.status into v_from_status
  from public.service_requests request
  where request.request_no = upper(trim(p_request_no))
  for update;

  if p_action = 'accept' then
    update public.service_requests request
    set status = 'accepted',
        accepted_at = coalesce(request.accepted_at, now()),
        current_actor = 'worker',
        next_action = 'confirm_arrival',
        updated_at = now()
    where request.request_no = upper(trim(p_request_no))
      and request.status = 'assigned'
    returning * into v_request;
    v_action := 'worker_accepted_task';
    v_note := '服务方已接单，等待确认到达';
  elsif p_action = 'arrive' then
    update public.service_requests request
    set status = 'arrived',
        arrived_at = coalesce(request.arrived_at, now()),
        current_actor = 'worker',
        next_action = 'prestart_confirmation',
        updated_at = now()
    where request.request_no = upper(trim(p_request_no))
      and request.status = 'accepted'
    returning * into v_request;
    v_action := 'worker_confirmed_arrival';
    v_note := '服务方已到达，进入开工前确认';
  else
    raise exception 'INVALID_WORKER_ACTION';
  end if;

  if not found then raise exception 'INVALID_TASK_STATE_TRANSITION'; end if;

  insert into public.task_events(
    request_no, event_type, action, actor_role,
    from_status, to_status, note, evidence
  ) values (
    v_request.request_no,
    'worker_transition',
    v_action,
    'worker',
    v_from_status,
    v_request.status,
    v_note,
    '{}'::jsonb
  );

  return jsonb_build_object(
    'request_no', v_request.request_no,
    'status', v_request.status,
    'current_actor', v_request.current_actor,
    'next_action', v_request.next_action,
    'accepted_at', v_request.accepted_at,
    'arrived_at', v_request.arrived_at
  );
end;
$function$;

revoke all on function public.save_platform_assignment_with_token(
  text, text, text, text, date, time without time zone, numeric, text, text, text, text
) from public;
grant execute on function public.save_platform_assignment_with_token(
  text, text, text, text, date, time without time zone, numeric, text, text, text, text
) to anon, authenticated;
revoke all on function public.transition_worker_task_with_token(text, text, text) from public;
grant execute on function public.transition_worker_task_with_token(text, text, text) to anon, authenticated;
