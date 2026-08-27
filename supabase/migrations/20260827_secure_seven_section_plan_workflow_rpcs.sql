-- Secure three-role seven-section implementation-plan workflow.
-- Applied to production and rollback-tested on 2026-08-27.

CREATE OR REPLACE FUNCTION public.read_implementation_plan_with_token(p_request_no text, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_no text := upper(trim(p_request_no));
  v_role text;
  v_order public.service_requests%rowtype;
  v_plan public.implementation_plans%rowtype;
  v_sections jsonb := '[]'::jsonb;
begin
  if public.validate_task_access_token(v_no,'worker',p_token) then
    v_role := 'worker';
  elsif public.validate_task_access_token(v_no,'customer',p_token) then
    v_role := 'customer';
  elsif public.validate_task_access_token(v_no,'platform',p_token)
     or exists (
       select 1
       from private.platform_dashboard_tokens t
       where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
         and t.revoked_at is null
         and t.expires_at>now()
     ) then
    v_role := 'platform';
  else
    raise exception 'PLAN_LINK_EXPIRED_OR_INVALID';
  end if;

  select * into v_order
  from public.service_requests
  where request_no=v_no;

  if not found then raise exception 'TASK_NOT_FOUND'; end if;

  select * into v_plan
  from public.implementation_plans
  where request_no=v_no and status<>'superseded'
  order by version desc
  limit 1;

  if found then
    select coalesce(jsonb_agg(jsonb_build_object(
      'code',s.section_code,
      'name',s.section_name_zh,
      'status',s.status,
      'content',s.content,
      'updated_at',s.updated_at
    ) order by case s.section_code
      when 'man' then 1 when 'machine' then 2 when 'material' then 3
      when 'method' then 4 when 'environment' then 5
      when 'schedule' then 6 when 'quality' then 7 else 99 end),'[]'::jsonb)
    into v_sections
    from public.plan_sections s
    where s.plan_id=v_plan.id;
  end if;

  return jsonb_build_object(
    'role',v_role,
    'order',jsonb_build_object(
      'request_no',v_order.request_no,
      'status',v_order.status,
      'service_type',v_order.service_type,
      'description',v_order.description,
      'address',v_order.address,
      'service_date',v_order.service_date,
      'duration',v_order.duration,
      'assigned_worker',v_order.assigned_worker,
      'worker_task_scope',v_order.worker_task_scope,
      'customer_acceptance_items',v_order.customer_acceptance_items,
      'current_actor',v_order.current_actor,
      'next_action',v_order.next_action,
      'work_started_at',v_order.work_started_at
    ),
    'plan',case when v_plan.id is null then null else jsonb_build_object(
      'id',v_plan.id,
      'request_no',v_plan.request_no,
      'version',v_plan.version,
      'status',v_plan.status,
      'content',v_plan.content,
      'review_note',v_plan.review_note,
      'approval_note',v_plan.approval_note,
      'platform_approval_status',v_plan.platform_approval_status,
      'submitted_at',v_plan.submitted_at,
      'approved_at',v_plan.approved_at,
      'customer_confirmed_at',v_plan.customer_confirmed_at,
      'prestart_ready',v_plan.prestart_ready,
      'sections',v_sections
    ) end
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.submit_implementation_plan_with_token(p_request_no text, p_token text, p_sections jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_no text := upper(trim(p_request_no));
  v_order public.service_requests%rowtype;
  v_latest public.implementation_plans%rowtype;
  v_plan public.implementation_plans%rowtype;
  v_version integer;
  v_code text;
  v_value text;
  v_now timestamptz := now();
  v_required text[] := array['man','machine','material','method','environment','schedule','quality'];
begin
  if not public.validate_task_access_token(v_no,'worker',p_token) then
    raise exception 'WORKER_PLAN_LINK_EXPIRED_OR_INVALID';
  end if;

  if jsonb_typeof(p_sections)<>'object' then
    raise exception 'SEVEN_PLAN_SECTIONS_REQUIRED';
  end if;

  foreach v_code in array v_required loop
    if jsonb_typeof(p_sections->v_code)<>'string' then
      raise exception 'PLAN_SECTION_REQUIRED: %',v_code;
    end if;
    v_value := trim(p_sections->>v_code);
    if length(v_value)<2 or length(v_value)>5000 then
      raise exception 'PLAN_SECTION_INVALID: %',v_code;
    end if;
  end loop;

  select * into v_order
  from public.service_requests
  where request_no=v_no
  for update;

  if not found then raise exception 'TASK_NOT_FOUND'; end if;
  if v_order.status not in ('assigned','accepted','arrived','arrival_confirmation','prestart_check') then
    raise exception 'TASK_NOT_READY_FOR_PLAN: %',v_order.status;
  end if;

  select * into v_latest
  from public.implementation_plans
  where request_no=v_no and status<>'superseded'
  order by version desc
  limit 1;

  if found and v_latest.status in ('submitted','under_review') then
    raise exception 'PLAN_ALREADY_AWAITING_REVIEW';
  end if;
  if found and v_latest.prestart_ready then
    raise exception 'PLAN_ALREADY_READY';
  end if;

  select coalesce(max(version),0)+1
  into v_version
  from public.implementation_plans
  where request_no=v_no;

  insert into public.implementation_plans(
    request_no,version,status,content,submitted_at,
    platform_approval_status,prestart_ready,updated_at
  ) values (
    v_no,v_version,'submitted',
    jsonb_build_object(
      'scope',coalesce(v_order.worker_task_scope,v_order.description),
      'method',trim(p_sections->>'method'),
      'quality_requirements',trim(p_sections->>'quality'),
      'safety',trim(p_sections->>'environment'),
      'resources',trim(p_sections->>'man'),
      'duration',trim(p_sections->>'schedule'),
      'sections',p_sections
    ),
    v_now,'pending',false,v_now
  )
  returning * into v_plan;

  update public.plan_sections s
  set status='completed',
      content=jsonb_build_object('detail',trim(p_sections->>s.section_code)),
      updated_at=v_now
  where s.plan_id=v_plan.id
    and s.section_code=any(v_required);

  update public.service_requests
  set active_plan_version=v_version,
      current_actor='platform',
      next_action='approve_implementation_plan',
      prework_agreement=coalesce(prework_agreement,'{}'::jsonb)||jsonb_build_object(
        'plan_version',v_version,
        'plan_status','submitted',
        'plan_submitted_at',v_now,
        'plan_approved_at',null,
        'plan_customer_confirmed_at',null
      ),
      updated_at=v_now
  where request_no=v_no;

  insert into public.task_events(
    request_no,event_type,action,actor_role,from_status,to_status,note,evidence
  ) values (
    v_no,'plan_workflow','worker_submit_seven_section_plan','worker',
    v_order.status,v_order.status,'服务方提交七章施工方案',
    jsonb_build_object('plan_id',v_plan.id,'version',v_version,'section_count',7)
  );

  return jsonb_build_object(
    'ok',true,'request_no',v_no,'plan_id',v_plan.id,
    'version',v_version,'status','submitted','section_count',7
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.review_implementation_plan_with_token(p_request_no text, p_token text, p_decision text, p_note text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_no text := upper(trim(p_request_no));
  v_plan public.implementation_plans%rowtype;
  v_order public.service_requests%rowtype;
  v_approved boolean;
  v_valid_count integer;
  v_now timestamptz := now();
begin
  if not (
    public.validate_task_access_token(v_no,'platform',p_token)
    or exists (
      select 1 from private.platform_dashboard_tokens t
      where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
        and t.revoked_at is null
        and t.expires_at>now()
    )
  ) then
    raise exception 'PLATFORM_PLAN_LINK_EXPIRED_OR_INVALID';
  end if;

  if p_decision not in ('approve','revision') then
    raise exception 'INVALID_PLAN_REVIEW_DECISION';
  end if;
  if length(coalesce(p_note,''))>2000 then
    raise exception 'PLAN_REVIEW_NOTE_TOO_LONG';
  end if;

  select * into v_order
  from public.service_requests
  where request_no=v_no
  for update;
  if not found then raise exception 'TASK_NOT_FOUND'; end if;

  select * into v_plan
  from public.implementation_plans
  where request_no=v_no and status='submitted'
  order by version desc
  limit 1
  for update;

  if not found then raise exception 'SUBMITTED_PLAN_NOT_FOUND'; end if;

  v_approved := p_decision='approve';

  if v_approved then
    select count(distinct section_code)
    into v_valid_count
    from public.plan_sections
    where plan_id=v_plan.id
      and section_code in ('man','machine','material','method','environment','schedule','quality')
      and status in ('completed','approved')
      and jsonb_typeof(content)='object'
      and length(trim(coalesce(content->>'detail','')))>1;

    if v_valid_count<>7 then
      raise exception 'SEVEN_COMPLETE_PLAN_SECTIONS_REQUIRED';
    end if;
  end if;

  update public.implementation_plans
  set status=case when v_approved then 'approved' else 'revision_requested' end,
      review_note=left(coalesce(p_note,''),2000),
      approval_note=left(coalesce(p_note,''),2000),
      approved_at=case when v_approved then v_now else null end,
      platform_approval_status=case when v_approved then 'approved' else 'pending' end,
      platform_approved_at=case when v_approved then v_now else null end,
      prestart_ready=false,
      updated_at=v_now
  where id=v_plan.id
  returning * into v_plan;

  update public.service_requests
  set current_actor=case when v_approved then 'customer' else 'worker' end,
      next_action=case when v_approved then 'confirm_implementation_plan' else 'revise_implementation_plan' end,
      prework_agreement=coalesce(prework_agreement,'{}'::jsonb)||jsonb_build_object(
        'plan_version',v_plan.version,
        'plan_status',v_plan.status,
        'plan_submitted_at',v_plan.submitted_at,
        'plan_approved_at',case when v_approved then v_now else null end,
        'plan_customer_confirmed_at',null
      ),
      updated_at=v_now
  where request_no=v_no;

  insert into public.task_events(
    request_no,event_type,action,actor_role,from_status,to_status,note,evidence
  ) values (
    v_no,'plan_workflow',
    case when v_approved then 'platform_approve_seven_section_plan' else 'platform_request_plan_revision' end,
    'platform',v_order.status,v_order.status,
    case when v_approved then '平台批准七章施工方案' else '平台退回施工方案修改' end,
    jsonb_build_object('plan_id',v_plan.id,'version',v_plan.version,'review_note',left(coalesce(p_note,''),2000))
  );

  return jsonb_build_object(
    'ok',true,'request_no',v_no,'plan_id',v_plan.id,
    'version',v_plan.version,'status',v_plan.status,
    'platform_approval_status',v_plan.platform_approval_status
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.confirm_assignment_plan_with_token(p_request_no text, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_no text := upper(trim(p_request_no));
  v_plan public.implementation_plans%rowtype;
  v_order public.service_requests%rowtype;
  v_valid_count integer;
  v_now timestamptz := now();
begin
  if not public.validate_task_access_token(v_no,'customer',p_token) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  select * into v_order
  from public.service_requests
  where request_no=v_no
  for update;
  if not found then raise exception 'TASK_NOT_FOUND'; end if;

  select * into v_plan
  from public.implementation_plans
  where request_no=v_no
    and platform_approval_status='approved'
    and status='approved'
  order by version desc
  limit 1
  for update;

  if not found then raise exception 'APPROVED_PLAN_NOT_FOUND'; end if;

  select count(distinct section_code)
  into v_valid_count
  from public.plan_sections
  where plan_id=v_plan.id
    and section_code in ('man','machine','material','method','environment','schedule','quality')
    and status in ('completed','approved')
    and jsonb_typeof(content)='object'
    and length(trim(coalesce(content->>'detail','')))>1;

  if v_valid_count<>7 then
    raise exception 'SEVEN_COMPLETE_PLAN_SECTIONS_REQUIRED';
  end if;

  update public.implementation_plans
  set status='customer_confirmed',
      customer_confirmed_at=coalesce(customer_confirmed_at,v_now),
      prestart_ready=false,
      updated_at=v_now
  where id=v_plan.id
  returning * into v_plan;

  update public.implementation_plans
  set prestart_ready=public.check_plan_prestart_ready(v_no),
      updated_at=v_now
  where id=v_plan.id
  returning * into v_plan;

  update public.service_requests
  set current_actor='worker',
      next_action='confirm_prework_and_upload_photos',
      prework_agreement=coalesce(prework_agreement,'{}'::jsonb)||jsonb_build_object(
        'plan_version',v_plan.version,
        'plan_status','customer_confirmed',
        'plan_submitted_at',v_plan.submitted_at,
        'plan_approved_at',v_plan.platform_approved_at,
        'plan_customer_confirmed_at',v_plan.customer_confirmed_at
      ),
      updated_at=v_now
  where request_no=v_no;

  insert into public.task_events(
    request_no,event_type,action,actor_role,from_status,to_status,note,evidence
  ) values (
    v_no,'plan_workflow','customer_confirm_seven_section_plan','customer',
    v_order.status,v_order.status,'客户确认七章施工方案',
    jsonb_build_object('plan_id',v_plan.id,'version',v_plan.version,'prestart_ready',v_plan.prestart_ready)
  );

  return jsonb_build_object(
    'request_no',v_plan.request_no,
    'version',v_plan.version,
    'status',v_plan.status,
    'customer_confirmed_at',v_plan.customer_confirmed_at,
    'prestart_ready',v_plan.prestart_ready,
    'current_actor','worker',
    'next_action','confirm_prework_and_upload_photos'
  );
end;
$function$


revoke all on function public.read_implementation_plan_with_token(text,text) from public,anon,authenticated;
revoke all on function public.submit_implementation_plan_with_token(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.review_implementation_plan_with_token(text,text,text,text) from public,anon,authenticated;
revoke all on function public.confirm_assignment_plan_with_token(text,text) from public,anon,authenticated;

grant execute on function public.read_implementation_plan_with_token(text,text) to anon,authenticated,service_role;
grant execute on function public.submit_implementation_plan_with_token(text,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.review_implementation_plan_with_token(text,text,text,text) to anon,authenticated,service_role;
grant execute on function public.confirm_assignment_plan_with_token(text,text) to anon,authenticated,service_role;
