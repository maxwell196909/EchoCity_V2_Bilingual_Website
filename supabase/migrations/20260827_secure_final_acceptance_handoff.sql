-- Secure customer final acceptance and remove the legacy phone-only API surface.

CREATE OR REPLACE FUNCTION public.get_customer_final_acceptance_with_token(p_request_no text, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_no text := upper(trim(p_request_no));
  v_request public.service_requests%rowtype;
  v_records jsonb;
  v_final_inspection public.task_inspections%rowtype;
  v_final_summary text;
  v_final_evidence text;
begin
  if not public.validate_task_access_token(v_request_no,'customer',p_token) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  select * into v_request
  from public.service_requests r
  where r.request_no=v_request_no
    and r.status in (
      'awaiting_final_acceptance','waiting_final_acceptance',
      'completed','conditionally_completed','final_rework','disputed','closed'
    );

  if not found then
    raise exception 'FINAL_ACCEPTANCE_ORDER_NOT_FOUND';
  end if;

  select * into v_final_inspection
  from public.task_inspections i
  where i.request_no=v_request_no
    and i.inspection_type='milestone'
    and i.status='platform_approved'
    and i.result='approved'
  order by i.sequence_no desc
  limit 1;

  if found then
    select item->>'value' into v_final_summary
    from jsonb_array_elements(v_final_inspection.checklist) item
    where item->>'code'='worker_summary'
    limit 1;
    v_final_evidence := nullif(v_final_inspection.evidence::text,'[]');
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'work_date',w.work_date,
    'work_hours',w.work_hours,
    'work_progress',w.work_progress,
    'materials_used',w.materials_used,
    'issues_found',w.issues_found,
    'photo_record',w.photo_record,
    'video_record',w.video_record,
    'customer_site_comment',w.customer_site_comment,
    'recorded_at',w.recorded_at
  )) order by w.work_date,w.created_at),'[]'::jsonb)
  into v_records
  from public.work_records w
  where w.request_no=v_request_no;

  return jsonb_build_object(
    'request',jsonb_strip_nulls(jsonb_build_object(
      'request_no',v_request.request_no,
      'status',v_request.status,
      'service_type',v_request.service_type,
      'description',v_request.description,
      'address',v_request.address,
      'completion_summary',coalesce(v_request.completion_summary,v_final_summary),
      'completion_evidence',coalesce(v_request.completion_evidence,v_final_evidence),
      'outstanding_issues',v_request.outstanding_issues,
      'customer_acceptance_focus',v_request.customer_acceptance_focus,
      'final_acceptance_status',v_request.final_acceptance_status,
      'final_acceptance_data',v_request.final_acceptance_data,
      'updated_at',v_request.updated_at
    )),
    'work_records',v_records
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.submit_customer_final_acceptance_with_token(p_request_no text, p_token text, p_final_result text, p_service_completed boolean, p_final_rating integer, p_final_comments text, p_outstanding_details text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_no text := upper(trim(p_request_no));
  v_customer_phone text;
begin
  if not public.validate_task_access_token(v_request_no,'customer',p_token) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  select r.customer_phone into v_customer_phone
  from public.service_requests r
  where r.request_no=v_request_no
  for update;

  if not found then
    raise exception 'CUSTOMER_ORDER_NOT_FOUND';
  end if;

  return public.submit_customer_final_acceptance(
    v_request_no,
    v_customer_phone,
    p_final_result,
    p_service_completed,
    p_final_rating,
    p_final_comments,
    p_outstanding_details
  );
end;
$function$


revoke all on function public.get_customer_final_acceptance_with_token(text,text) from public;
grant execute on function public.get_customer_final_acceptance_with_token(text,text) to anon, authenticated;

revoke all on function public.submit_customer_final_acceptance_with_token(text,text,text,boolean,integer,text,text) from public;
grant execute on function public.submit_customer_final_acceptance_with_token(text,text,text,boolean,integer,text,text) to anon, authenticated;

revoke all on function public.get_customer_final_acceptance(text,text) from public, anon, authenticated;
revoke all on function public.submit_customer_final_acceptance(text,text,text,boolean,integer,text,text) from public, anon, authenticated;
