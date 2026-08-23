begin;

create or replace function public.get_customer_final_acceptance(
  p_request_no text,
  p_customer_phone text
) returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_records jsonb;
begin
  if length(regexp_replace(coalesce(p_customer_phone,''),'\D','','g')) < 7 then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  select * into v_request
  from public.service_requests r
  where r.request_no = upper(trim(p_request_no))
    and regexp_replace(coalesce(r.customer_phone,''),'\D','','g') = regexp_replace(p_customer_phone,'\D','','g')
    and r.status in ('awaiting_final_acceptance','completed','conditionally_completed','final_rework','disputed');

  if not found then raise exception 'FINAL_ACCEPTANCE_ORDER_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'work_date',w.work_date,
    'work_hours',w.work_hours,
    'work_progress',w.work_progress,
    'materials_used',w.materials_used,
    'issues_found',w.issues_found
  ) order by w.work_date,w.created_at),'[]'::jsonb)
  into v_records
  from public.work_records w
  where w.request_no=v_request.request_no;

  return jsonb_build_object(
    'request', jsonb_build_object(
      'request_no',v_request.request_no,
      'status',v_request.status,
      'service_type',v_request.service_type,
      'description',v_request.description,
      'address',v_request.address,
      'final_acceptance_status',v_request.final_acceptance_status,
      'final_acceptance_data',v_request.final_acceptance_data,
      'updated_at',v_request.updated_at
    ),
    'work_records',v_records
  );
end;
$function$;

create or replace function public.submit_customer_final_acceptance(
  p_request_no text,
  p_customer_phone text,
  p_final_result text,
  p_service_completed boolean,
  p_final_rating integer,
  p_final_comments text,
  p_outstanding_details text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.service_requests%rowtype;
  v_status text;
  v_actor text;
  v_next text;
  v_data jsonb;
  v_record_count integer;
  v_total_hours numeric;
begin
  if p_final_result not in ('accepted','conditional','rework','disputed') then raise exception 'INVALID_FINAL_RESULT'; end if;
  if p_final_rating not between 1 and 5 then raise exception 'INVALID_FINAL_RATING'; end if;
  if length(trim(coalesce(p_final_comments,''))) < 2 or length(p_final_comments)>2000 then raise exception 'INVALID_FINAL_COMMENTS'; end if;
  if p_final_result='accepted' and not coalesce(p_service_completed,false) then raise exception 'ACCEPTED_REQUIRES_COMPLETION'; end if;

  select * into v_request
  from public.service_requests r
  where r.request_no=upper(trim(p_request_no))
    and regexp_replace(coalesce(r.customer_phone,''),'\D','','g')=regexp_replace(coalesce(p_customer_phone,''),'\D','','g')
  for update;
  if not found then raise exception 'CUSTOMER_ORDER_NOT_FOUND'; end if;
  if v_request.status <> 'awaiting_final_acceptance' then raise exception 'ORDER_NOT_READY_FOR_FINAL_ACCEPTANCE'; end if;

  v_status := case p_final_result when 'accepted' then 'completed' when 'conditional' then 'conditionally_completed' when 'rework' then 'final_rework' else 'disputed' end;
  v_actor := case when p_final_result='rework' then 'worker' else 'platform' end;
  v_next := case p_final_result when 'accepted' then 'settle_order' when 'conditional' then 'review_conditions_and_settle' when 'rework' then 'rectify_final_acceptance' else 'resolve_dispute' end;

  select count(*),coalesce(sum(work_hours),0) into v_record_count,v_total_hours
  from public.work_records where request_no=v_request.request_no;

  v_data := jsonb_build_object(
    'request_no',v_request.request_no,
    'submitted_at',now(),
    'final_result',p_final_result,
    'service_completed',p_service_completed,
    'final_rating',p_final_rating,
    'final_comments',trim(p_final_comments),
    'outstanding_details',nullif(trim(coalesce(p_outstanding_details,'')),''),
    'reviewed_all_records',true,
    'confirmed_final_site',true,
    'truth_confirmed',true,
    'work_record_count',v_record_count,
    'total_work_hours',v_total_hours
  );

  update public.service_requests
  set status=v_status,
      final_acceptance_status=p_final_result,
      final_acceptance_data=v_data,
      current_actor=v_actor,
      next_action=v_next,
      updated_at=now()
  where request_no=v_request.request_no;

  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence)
  values(v_request.request_no,'final_acceptance','customer_final_'||p_final_result,'customer',v_request.status,v_status,trim(p_final_comments),jsonb_build_object('rating',p_final_rating,'service_completed',p_service_completed));

  return jsonb_build_object('request_no',v_request.request_no,'status',v_status,'next_action',v_next);
end;
$function$;

revoke all on function public.get_customer_final_acceptance(text,text) from public,anon,authenticated;
revoke all on function public.submit_customer_final_acceptance(text,text,text,boolean,integer,text,text) from public,anon,authenticated;
grant execute on function public.get_customer_final_acceptance(text,text) to anon,authenticated,service_role;
grant execute on function public.submit_customer_final_acceptance(text,text,text,boolean,integer,text,text) to anon,authenticated,service_role;

commit;
