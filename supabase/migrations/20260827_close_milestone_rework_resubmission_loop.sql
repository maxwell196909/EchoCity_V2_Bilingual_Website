-- Close the milestone remediation loop with fresh-record and fresh-evidence gates.

CREATE OR REPLACE FUNCTION public.submit_milestone_with_token(p_request_no text, p_token text, p_summary text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_no text := upper(trim(p_request_no));
  v_request public.service_requests%rowtype;
  v_sequence integer;
  v_id uuid;
  v_evidence jsonb;
  v_is_rework boolean;
  v_rejected_at timestamptz;
begin
  if not public.validate_task_access_token(v_request_no,'worker',p_token) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;
  if length(trim(coalesce(p_summary,''))) not between 2 and 2000 then
    raise exception 'INVALID_MILESTONE_SUMMARY';
  end if;

  select * into v_request
  from public.service_requests r
  where r.request_no=v_request_no
  for update;

  if not found or v_request.status not in ('in_progress','working','milestone_approved','milestone_rework') then
    raise exception 'TASK_NOT_READY_FOR_MILESTONE';
  end if;

  v_is_rework := v_request.status='milestone_rework'
    or v_request.next_action in ('rectify_milestone','submit_milestone_reinspection');

  if v_is_rework then
    select max(i.reviewed_at) into v_rejected_at
    from public.task_inspections i
    where i.request_no=v_request_no
      and i.inspection_type='milestone'
      and i.result='rework'
      and i.status in ('rework_required','platform_rework');

    if v_rejected_at is null then
      raise exception 'REWORK_DECISION_NOT_FOUND';
    end if;

    if not exists (
      select 1 from public.work_records w
      where w.request_no=v_request_no
        and w.recorded_at > v_rejected_at
    ) then
      raise exception 'NEW_REWORK_RECORD_REQUIRED';
    end if;

    select coalesce(jsonb_agg(
      jsonb_build_object('storage_path',e.storage_path,'media_type',e.media_type)
      order by e.created_at desc
    ),'[]'::jsonb)
    into v_evidence
    from (
      select * from public.task_evidence
      where request_no=v_request_no
        and stage_code='construction_rework'
        and evidence_code='milestone_rework_progress'
        and created_at > v_rejected_at
      order by created_at desc
      limit 10
    ) e;

    if jsonb_array_length(v_evidence)=0 then
      raise exception 'NEW_REWORK_EVIDENCE_REQUIRED';
    end if;
  else
    if v_request.latest_work_progress is null then
      raise exception 'WORK_RECORD_REQUIRED';
    end if;

    select coalesce(jsonb_agg(
      jsonb_build_object('storage_path',e.storage_path,'media_type',e.media_type)
      order by e.created_at desc
    ),'[]'::jsonb)
    into v_evidence
    from (
      select * from public.task_evidence
      where request_no=v_request_no
        and stage_code in ('construction','process','work_progress')
      order by created_at desc
      limit 10
    ) e;

    if jsonb_array_length(v_evidence)=0 then
      raise exception 'PROCESS_EVIDENCE_REQUIRED';
    end if;
  end if;

  select coalesce(max(sequence_no),0)+1 into v_sequence
  from public.task_inspections
  where request_no=v_request_no and inspection_type='milestone';

  insert into public.task_inspections(
    request_no,inspection_type,sequence_no,status,result,checklist,evidence,
    submitted_role,submitted_at,next_stage
  ) values (
    v_request_no,'milestone',v_sequence,'submitted','pending',
    jsonb_build_array(jsonb_build_object(
      'code','worker_summary','value',trim(p_summary),'rework_resubmission',v_is_rework
    )),
    v_evidence,'worker',now(),'customer_review'
  ) returning id into v_id;

  update public.service_requests
  set status='milestone_submitted',
      workflow_stage='construction',
      current_actor='customer',
      next_action='review_milestone',
      updated_at=now()
  where request_no=v_request_no;

  insert into public.task_events(
    request_no,event_type,action,actor_role,from_status,to_status,note,evidence
  ) values (
    v_request_no,'status_transition',
    case when v_is_rework then 'resubmit_milestone_after_rework' else 'submit_milestone' end,
    'worker',v_request.status,'milestone_submitted',trim(p_summary),
    jsonb_build_object(
      'inspection_id',v_id,'sequence_no',v_sequence,'rework_resubmission',v_is_rework
    )
  );

  return jsonb_build_object(
    'request_no',v_request_no,'status','milestone_submitted',
    'inspection_id',v_id,'sequence_no',v_sequence,'rework_resubmission',v_is_rework
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.submit_work_record_with_token(p_request_no text, p_token text, p_work_progress text, p_materials_used text DEFAULT NULL::text, p_issues_found text DEFAULT NULL::text, p_work_hours numeric DEFAULT NULL::numeric, p_storage_path text DEFAULT NULL::text, p_file_name text DEFAULT NULL::text, p_file_size bigint DEFAULT NULL::bigint, p_mime_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_no text := upper(trim(p_request_no));
  v_task public.service_requests%rowtype;
  v_phone text;
  v_prefix text;
  v_record_id bigint;
  v_evidence_id uuid;
  v_is_rework boolean;
  v_target_status text;
  v_next_action text;
begin
  if not public.validate_task_access_token(v_request_no, 'worker', p_token) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  if p_work_progress is null or length(trim(p_work_progress)) < 2 or length(p_work_progress) > 2000 then
    raise exception 'WORK_PROGRESS_REQUIRED';
  end if;
  if p_work_hours is not null and (p_work_hours < 0 or p_work_hours > 24) then
    raise exception 'INVALID_WORK_HOURS';
  end if;

  select * into v_task
  from public.service_requests request
  where request.request_no = v_request_no
  for update;

  if not found then raise exception 'TASK_NOT_FOUND'; end if;
  if v_task.status not in ('in_progress','working','milestone_rework') or v_task.work_started_at is null then
    raise exception 'TASK_NOT_IN_PROGRESS';
  end if;

  v_is_rework := v_task.status = 'milestone_rework';
  if v_is_rework and p_storage_path is null then
    raise exception 'REWORK_PHOTO_REQUIRED';
  end if;

  v_phone := regexp_replace(coalesce(v_task.assigned_worker_phone, ''), '[^0-9]', '', 'g');
  if p_storage_path is not null then
    if p_file_name is null or p_file_size is null or p_file_size < 1 or p_file_size > 10485760
       or p_mime_type not in ('image/jpeg','image/png','image/webp','image/heic','image/heif') then
      raise exception 'INVALID_WORK_PHOTO';
    end if;
    v_prefix := v_request_no || '/' || v_phone || '/process-photos/';
    if v_phone = '' or left(p_storage_path, length(v_prefix)) <> v_prefix then
      raise exception 'INVALID_EVIDENCE_PATH';
    end if;
    if not exists (
      select 1 from storage.objects object
      where object.bucket_id='work-evidence' and object.name=p_storage_path
    ) then
      raise exception 'WORK_PHOTO_UPLOAD_NOT_FOUND';
    end if;
  end if;

  insert into public.work_records(
    request_no, worker_phone, work_date, work_hours, work_progress,
    materials_used, issues_found, photo_record, recorded_at
  ) values (
    v_request_no, v_task.assigned_worker_phone, current_date, p_work_hours,
    trim(p_work_progress), nullif(trim(coalesce(p_materials_used,'')),''),
    nullif(trim(coalesce(p_issues_found,'')),''),
    p_storage_path, now()
  ) returning id into v_record_id;

  if p_storage_path is not null then
    insert into public.task_evidence(
      request_no, stage_code, evidence_code, media_type, storage_path,
      captured_at, uploader_role, file_metadata
    ) values (
      v_request_no,
      case when v_is_rework then 'construction_rework' else 'construction' end,
      case when v_is_rework then 'milestone_rework_progress' else 'work_progress' end,
      'photo', p_storage_path, now(), 'worker', jsonb_build_object(
        'work_record_id',v_record_id,
        'original_name',left(p_file_name,255),
        'size',p_file_size,
        'mime_type',p_mime_type,
        'source','dedicated_link',
        'rework',v_is_rework
      )
    ) returning id into v_evidence_id;
  end if;

  v_target_status := case when v_is_rework then 'milestone_rework' else 'in_progress' end;
  v_next_action := case when v_is_rework then 'submit_milestone_reinspection' else 'record_work' end;

  update public.service_requests
  set status=v_target_status,
      workflow_stage=case when v_is_rework then 'construction_rework' else 'construction' end,
      current_actor='worker',
      next_action=v_next_action,
      latest_work_date=current_date,
      latest_work_progress=trim(p_work_progress),
      latest_work_hours=p_work_hours,
      latest_materials_used=nullif(trim(coalesce(p_materials_used,'')),''),
      latest_issues_found=nullif(trim(coalesce(p_issues_found,'')),''),
      latest_photo_record=p_storage_path,
      latest_work_recorded_at=now(),
      updated_at=now()
  where request_no=v_request_no;

  insert into public.task_events(
    request_no,event_type,action,actor_role,from_status,to_status,note,evidence
  ) values (
    v_request_no,'work_record',
    case when v_is_rework then 'worker_record_milestone_rework' else 'worker_record_progress' end,
    'worker',v_task.status,v_target_status,left(trim(p_work_progress),500),
    jsonb_strip_nulls(jsonb_build_object(
      'work_record_id',v_record_id,'evidence_id',v_evidence_id,
      'storage_path',p_storage_path,'rework',v_is_rework
    ))
  );

  perform public.enqueue_ai_work(
    case when v_is_rework then 'milestone_rework_submitted' else 'work_progress_submitted' end,
    v_request_no,
    jsonb_strip_nulls(jsonb_build_object(
      'work_record_id',v_record_id,'evidence_id',v_evidence_id,
      'progress',trim(p_work_progress),
      'issues',nullif(trim(coalesce(p_issues_found,'')),''),
      'rework',v_is_rework
    ))
  );

  return jsonb_build_object(
    'request_no',v_request_no,
    'status',v_target_status,
    'workflow_stage',case when v_is_rework then 'construction_rework' else 'construction' end,
    'next_action',v_next_action,
    'work_record_id',v_record_id,
    'evidence_id',v_evidence_id,
    'recorded_at',now()
  );
end;
$function$


revoke all on function public.submit_work_record_with_token(text,text,text,text,text,numeric,text,text,bigint,text) from public;
grant execute on function public.submit_work_record_with_token(text,text,text,text,text,numeric,text,text,bigint,text) to anon, authenticated;

revoke all on function public.submit_milestone_with_token(text,text,text) from public;
grant execute on function public.submit_milestone_with_token(text,text,text) to anon, authenticated;
