begin;
create or replace function public.review_milestone_with_token(p_request_no text,p_token text,p_accept boolean,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_request public.service_requests%rowtype; v_inspection public.task_inspections%rowtype;
begin
  if not public.validate_task_access_token(upper(trim(p_request_no)),'customer',p_token) then raise exception 'TASK_LINK_EXPIRED_OR_INVALID'; end if;
  if length(coalesce(p_note,''))>2000 then raise exception 'REVIEW_NOTE_TOO_LONG'; end if;
  select * into v_request from public.service_requests r where r.request_no=upper(trim(p_request_no)) for update;
  if not found or v_request.status<>'milestone_submitted' then raise exception 'MILESTONE_NOT_READY_FOR_CUSTOMER_REVIEW'; end if;
  update public.task_inspections i set status=case when p_accept then 'customer_approved' else 'rework_required' end,
    result=case when p_accept then 'approved' else 'rework' end,reviewer_role='customer',reviewed_at=now(),review_note=nullif(trim(p_note),''),
    next_stage=case when p_accept then 'platform_review' else 'construction_rework' end,updated_at=now()
  where i.id=(select i2.id from public.task_inspections i2 where i2.request_no=v_request.request_no and i2.inspection_type='milestone' and i2.status='submitted' order by i2.sequence_no desc limit 1)
  returning * into v_inspection;
  if not found then raise exception 'SUBMITTED_MILESTONE_NOT_FOUND'; end if;
  update public.service_requests set status=case when p_accept then 'milestone_customer_approved' else 'milestone_rework' end,
    current_actor=case when p_accept then 'platform' else 'worker' end,next_action=case when p_accept then 'platform_review_milestone' else 'rectify_milestone' end,updated_at=now()
  where request_no=v_request.request_no;
  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence)
  values(v_request.request_no,'inspection_review',case when p_accept then 'customer_approve_milestone' else 'customer_request_rework' end,'customer',v_request.status,
    case when p_accept then 'milestone_customer_approved' else 'milestone_rework' end,nullif(trim(p_note),''),jsonb_build_object('inspection_id',v_inspection.id));
  return jsonb_build_object('request_no',v_request.request_no,'status',case when p_accept then 'milestone_customer_approved' else 'milestone_rework' end,'accepted',p_accept,'sequence_no',v_inspection.sequence_no);
end;$function$;
revoke all on function public.review_milestone_with_token(text,text,boolean,text) from public,anon,authenticated;
grant execute on function public.review_milestone_with_token(text,text,boolean,text) to anon,authenticated,service_role;
commit;
