-- Enforce the complete seven-section implementation-plan gate before work starts.
-- Production migration applied and rollback-tested on 2026-08-27.

create or replace function public.check_plan_prestart_ready(p_request_no text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_plan public.implementation_plans%rowtype;
  v_required_count integer;
  v_invalid_count integer;
begin
  select *
  into v_plan
  from public.implementation_plans
  where request_no = upper(trim(p_request_no))
    and platform_approval_status = 'approved'
    and customer_confirmed_at is not null
  order by version desc
  limit 1;

  if not found then
    return false;
  end if;

  select
    count(distinct section_code) filter (
      where section_code in (
        'man','machine','material','method',
        'environment','schedule','quality'
      )
    ),
    count(*) filter (
      where section_code in (
        'man','machine','material','method',
        'environment','schedule','quality'
      )
      and (
        status not in ('completed','approved')
        or jsonb_typeof(content) <> 'object'
        or case
          when jsonb_typeof(content) = 'object' then
            not exists (
              select 1
              from jsonb_object_keys(content) as content_key
              where content_key <> 'required_fields'
            )
          else true
        end
      )
    )
  into v_required_count, v_invalid_count
  from public.plan_sections
  where plan_id = v_plan.id;

  return v_required_count = 7 and v_invalid_count = 0;
end;
$function$;

create or replace function public.enforce_prestart_plan_gate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.workflow_stage is distinct from old.workflow_stage
     and (
       new.workflow_stage = 'prestart'
       or (
         new.workflow_stage = 'construction'
         and new.work_started_at is not null
         and old.work_started_at is null
       )
     )
     and not public.check_plan_prestart_ready(new.request_no)
  then
    raise exception 'COMPLETE_APPROVED_CUSTOMER_CONFIRMED_PLAN_REQUIRED';
  end if;

  return new;
end;
$function$;

create or replace function public.confirm_assignment_plan_with_token(
  p_request_no text,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_plan public.implementation_plans%rowtype;
begin
  if not public.validate_task_access_token(
    upper(trim(p_request_no)),
    'customer',
    p_token
  ) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  update public.implementation_plans p
  set status = 'customer_confirmed',
      customer_confirmed_at = coalesce(p.customer_confirmed_at, now()),
      prestart_ready = false,
      updated_at = now()
  where p.id = (
    select p2.id
    from public.implementation_plans p2
    where p2.request_no = upper(trim(p_request_no))
      and p2.platform_approval_status = 'approved'
    order by p2.version desc
    limit 1
  )
  returning * into v_plan;

  if not found then
    raise exception 'APPROVED_PLAN_NOT_FOUND';
  end if;

  update public.implementation_plans
  set prestart_ready = public.check_plan_prestart_ready(v_plan.request_no),
      updated_at = now()
  where id = v_plan.id
  returning * into v_plan;

  return jsonb_build_object(
    'request_no', v_plan.request_no,
    'version', v_plan.version,
    'status', v_plan.status,
    'customer_confirmed_at', v_plan.customer_confirmed_at,
    'prestart_ready', v_plan.prestart_ready
  );
end;
$function$;

create or replace function public.seed_plan_sections_after_insert()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform public.seed_plan_sections(new.id);
  return new;
end;
$function$;

drop trigger if exists trg_seed_plan_sections_after_insert
on public.implementation_plans;

create trigger trg_seed_plan_sections_after_insert
after insert on public.implementation_plans
for each row execute function public.seed_plan_sections_after_insert();

select public.seed_plan_sections(p.id)
from public.implementation_plans p;

update public.implementation_plans p
set prestart_ready = false,
    updated_at = now()
from public.service_requests r
where r.request_no = p.request_no
  and r.work_started_at is null
  and p.prestart_ready = true
  and not public.check_plan_prestart_ready(p.request_no);

revoke execute on function public.seed_plan_sections_after_insert()
from public, anon, authenticated;
