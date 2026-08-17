-- EchoCity dedicated task-link gateway
-- Stage 1: issue, validate and read role-scoped task links.

begin;

create or replace function public.issue_task_access_token(
  p_request_no text,
  p_role text,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
begin
  if p_role not in ('customer', 'worker', 'platform') then
    raise exception 'INVALID_LINK_ROLE';
  end if;

  if p_valid_hours < 1 or p_valid_hours > 720 then
    raise exception 'INVALID_LINK_DURATION';
  end if;

  if not exists (
    select 1
    from public.service_requests request
    where request.request_no = p_request_no
  ) then
    raise exception 'TASK_NOT_FOUND';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.task_access_tokens (
    request_no,
    role,
    token_hash,
    expires_at
  ) values (
    p_request_no,
    p_role,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    now() + make_interval(hours => p_valid_hours)
  );

  return v_token;
end;
$function$;

revoke all on function public.issue_task_access_token(text, text, integer)
  from public, anon, authenticated;
grant execute on function public.issue_task_access_token(text, text, integer)
  to service_role;

create or replace function public.read_task_with_token(
  p_request_no text,
  p_token text,
  p_role text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_result jsonb;
begin
  if p_request_no is null
     or length(p_request_no) > 80
     or p_token is null
     or length(p_token) < 32
     or p_role not in ('customer', 'worker', 'platform') then
    raise exception 'INVALID_TASK_LINK';
  end if;

  if not exists (
    select 1
    from public.task_access_tokens access_token
    where access_token.request_no = p_request_no
      and access_token.role = p_role
      and access_token.token_hash =
        encode(extensions.digest(p_token, 'sha256'), 'hex')
      and access_token.revoked_at is null
      and access_token.expires_at > now()
  ) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  select *
  into v_request
  from public.service_requests request
  where request.request_no = p_request_no;

  if not found then
    raise exception 'TASK_NOT_FOUND';
  end if;

  v_result := jsonb_build_object(
    'request_no', v_request.request_no,
    'service_type', v_request.service_type,
    'description', v_request.description,
    'service_date', v_request.service_date,
    'start_time', v_request.start_time,
    'duration', v_request.duration,
    'address', v_request.address,
    'status', v_request.status,
    'workflow_stage', v_request.workflow_stage,
    'current_actor', v_request.current_actor,
    'next_action', v_request.next_action,
    'risk_level', v_request.risk_level,
    'assigned_worker', v_request.assigned_worker,
    'assigned_start_time', v_request.assigned_start_time,
    'worker_task_scope', v_request.worker_task_scope,
    'accepted_at', v_request.accepted_at,
    'arrived_at', v_request.arrived_at,
    'work_started_at', v_request.work_started_at,
    'work_completed_at', v_request.work_completed_at,
    'plans', coalesce((
      select jsonb_agg(to_jsonb(plan) order by plan.version desc)
      from public.implementation_plans plan
      where plan.request_no = p_request_no
    ), '[]'::jsonb),
    'inspections', coalesce((
      select jsonb_agg(to_jsonb(inspection) order by inspection.created_at)
      from public.task_inspections inspection
      where inspection.request_no = p_request_no
    ), '[]'::jsonb),
    'evidence', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', evidence.id,
          'stage_code', evidence.stage_code,
          'evidence_code', evidence.evidence_code,
          'media_type', evidence.media_type,
          'storage_path', evidence.storage_path,
          'thumbnail_path', evidence.thumbnail_path,
          'captured_at', evidence.captured_at,
          'uploader_role', evidence.uploader_role,
          'ai_status', evidence.ai_status,
          'ai_score', evidence.ai_score,
          'human_status', evidence.human_status,
          'created_at', evidence.created_at
        ) order by evidence.created_at
      )
      from public.task_evidence evidence
      where evidence.request_no = p_request_no
    ), '[]'::jsonb)
  );

  if p_role in ('customer', 'platform') then
    v_result := v_result || jsonb_build_object(
      'customer_name', v_request.customer_name,
      'customer_phone', v_request.customer_phone,
      'quote_amount', v_request.quote_amount,
      'quote_note', v_request.quote_note,
      'quote_confirmed', v_request.quote_confirmed,
      'final_acceptance_status', v_request.final_acceptance_status
    );
  end if;

  if p_role in ('worker', 'platform') then
    v_result := v_result || jsonb_build_object(
      'customer_name', v_request.customer_name,
      'customer_phone', v_request.customer_phone,
      'prework_agreement', v_request.prework_agreement,
      'latest_work_progress', v_request.latest_work_progress,
      'latest_issues_found', v_request.latest_issues_found,
      'completion_summary', v_request.completion_summary,
      'outstanding_issues', v_request.outstanding_issues
    );
  end if;

  if p_role = 'platform' then
    v_result := v_result || jsonb_build_object(
      'worker_id', v_request.worker_id,
      'customer_id', v_request.customer_id,
      'platform_owner_id', v_request.platform_owner_id,
      'assigned_worker_phone', v_request.assigned_worker_phone,
      'worker_pay', v_request.worker_pay,
      'funding_route', v_request.funding_route,
      'ai_triage', v_request.ai_triage
    );
  end if;

  return v_result;
end;
$function$;

revoke all on function public.read_task_with_token(text, text, text)
  from public;
grant execute on function public.read_task_with_token(text, text, text)
  to anon, authenticated, service_role;

create or replace function public.revoke_task_access_tokens(
  p_request_no text,
  p_role text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  update public.task_access_tokens access_token
  set revoked_at = now()
  where access_token.request_no = p_request_no
    and access_token.revoked_at is null
    and (p_role is null or access_token.role = p_role);

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke all on function public.revoke_task_access_tokens(text, text)
  from public, anon, authenticated;
grant execute on function public.revoke_task_access_tokens(text, text)
  to service_role;

comment on function public.issue_task_access_token(text, text, integer) is
  'Backend-only issuer for time-limited customer, worker and platform links.';
comment on function public.read_task_with_token(text, text, text) is
  'Role-scoped task reader for a valid time-limited bearer link.';
comment on function public.revoke_task_access_tokens(text, text) is
  'Backend-only revocation for task links.';

commit;

-- This stage is read-only. Role-specific write actions will be introduced only
-- after the customer, worker and platform pages use this gateway successfully.
