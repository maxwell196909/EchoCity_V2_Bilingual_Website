begin;
create or replace function public.get_platform_milestone_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
declare v_request public.service_requests%rowtype; v_inspection public.task_inspections%rowtype;
begin
  if p_token is null or length(p_token)<64 or not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select * into v_request from public.service_requests r where r.request_no=upper(trim(p_request_no)); if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  select * into v_inspection from public.task_inspections i where i.request_no=v_request.request_no and i.inspection_type='milestone' order by i.sequence_no desc limit 1; if not found then raise exception 'MILESTONE_NOT_FOUND'; end if;
  return jsonb_build_object('request_no',v_request.request_no,'status',v_request.status,'latest_work_progress',v_request.latest_work_progress,'latest_issues_found',v_request.latest_issues_found,'sequence_no',v_inspection.sequence_no,'inspection_status',v_inspection.status,'customer_note',v_inspection.review_note,'evidence_count',jsonb_array_length(v_inspection.evidence));
end;$function$;
create or replace function public.review_platform_milestone_with_token(p_request_no text,p_token text,p_decision text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_request public.service_requests%rowtype; v_inspection public.task_inspections%rowtype; v_status text; v_next text; v_actor text;
begin
  if p_token is null or length(p_token)<64 or not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if p_decision not in ('continue','finish','rework') then raise exception 'INVALID_PLATFORM_DECISION'; end if;
  if length(coalesce(p_note,''))>2000 or (p_decision='rework' and length(trim(coalesce(p_note,'')))<2) then raise exception 'INVALID_REVIEW_NOTE'; end if;
  select * into v_request from public.service_requests r where r.request_no=upper(trim(p_request_no)) for update;
  if not found or v_request.status<>'milestone_customer_approved' then raise exception 'MILESTONE_NOT_READY_FOR_PLATFORM_REVIEW'; end if;
  v_status:=case p_decision when 'continue' then 'in_progress' when 'finish' then 'awaiting_final_acceptance' else 'milestone_rework' end; v_actor:=case when p_decision='finish' then 'customer' else 'worker' end; v_next:=case p_decision when 'continue' then 'record_work' when 'finish' then 'final_acceptance' else 'rectify_milestone' end;
  update public.task_inspections i set status=case when p_decision='rework' then 'platform_rework' else 'platform_approved' end,result=case when p_decision='rework' then 'rework' else 'approved' end,reviewer_role='platform',reviewed_at=now(),review_note=concat_ws(E'\n',i.review_note,nullif(trim(p_note),'')),next_stage=v_next,updated_at=now()
  where i.id=(select i2.id from public.task_inspections i2 where i2.request_no=v_request.request_no and i2.inspection_type='milestone' and i2.status='customer_approved' order by i2.sequence_no desc limit 1) returning * into v_inspection;
  if not found then raise exception 'CUSTOMER_APPROVED_MILESTONE_NOT_FOUND'; end if;
  update public.service_requests set status=v_status,current_actor=v_actor,next_action=v_next,updated_at=now() where request_no=v_request.request_no;
  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence) values(v_request.request_no,'inspection_review','platform_'||p_decision||'_milestone','platform',v_request.status,v_status,nullif(trim(p_note),''),jsonb_build_object('inspection_id',v_inspection.id));
  return jsonb_build_object('request_no',v_request.request_no,'status',v_status,'decision',p_decision);
end;$function$;
revoke all on function public.get_platform_milestone_with_token(text,text) from public,anon,authenticated;
revoke all on function public.review_platform_milestone_with_token(text,text,text,text) from public,anon,authenticated;
grant execute on function public.get_platform_milestone_with_token(text,text) to anon,authenticated,service_role;
grant execute on function public.review_platform_milestone_with_token(text,text,text,text) to anon,authenticated,service_role;
commit;
