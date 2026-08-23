begin;
create or replace function public.submit_milestone_with_token(p_request_no text,p_token text,p_summary text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_request public.service_requests%rowtype; v_sequence integer; v_id uuid; v_evidence jsonb;
begin
  if not public.validate_task_access_token(upper(trim(p_request_no)),'worker',p_token) then raise exception 'TASK_LINK_EXPIRED_OR_INVALID'; end if;
  if length(trim(coalesce(p_summary,''))) not between 2 and 2000 then raise exception 'INVALID_MILESTONE_SUMMARY'; end if;
  select * into v_request from public.service_requests r where r.request_no=upper(trim(p_request_no)) for update;
  if not found or v_request.status not in ('in_progress','working','milestone_approved') then raise exception 'TASK_NOT_READY_FOR_MILESTONE'; end if;
  if v_request.latest_work_progress is null then raise exception 'WORK_RECORD_REQUIRED'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('storage_path',e.storage_path,'media_type',e.media_type) order by e.created_at desc),'[]'::jsonb)
    into v_evidence from (select * from public.task_evidence where request_no=v_request.request_no and stage_code in ('construction','process','work_progress') order by created_at desc limit 10) e;
  if jsonb_array_length(v_evidence)=0 then raise exception 'PROCESS_EVIDENCE_REQUIRED'; end if;
  select coalesce(max(sequence_no),0)+1 into v_sequence from public.task_inspections where request_no=v_request.request_no and inspection_type='milestone';
  insert into public.task_inspections(request_no,inspection_type,sequence_no,status,result,checklist,evidence,submitted_role,submitted_at,next_stage)
  values(v_request.request_no,'milestone',v_sequence,'submitted','pending',jsonb_build_array(jsonb_build_object('code','worker_summary','value',trim(p_summary))),v_evidence,'worker',now(),'customer_review') returning id into v_id;
  update public.service_requests set status='milestone_submitted',current_actor='customer',next_action='review_milestone',updated_at=now() where request_no=v_request.request_no;
  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence)
  values(v_request.request_no,'status_transition','submit_milestone','worker',v_request.status,'milestone_submitted',trim(p_summary),jsonb_build_object('inspection_id',v_id,'sequence_no',v_sequence));
  return jsonb_build_object('request_no',v_request.request_no,'status','milestone_submitted','inspection_id',v_id,'sequence_no',v_sequence);
end;$function$;
revoke all on function public.submit_milestone_with_token(text,text,text) from public,anon,authenticated;
grant execute on function public.submit_milestone_with_token(text,text,text) to anon,authenticated,service_role;
commit;
