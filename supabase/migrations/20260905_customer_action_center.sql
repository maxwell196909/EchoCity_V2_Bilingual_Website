create or replace function public.get_customer_progress_timeline_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_no text:=upper(trim(p_request_no)); r public.service_requests;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into r from public.service_requests where request_no=v_no;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  return jsonb_build_object(
    'request',jsonb_build_object('request_no',r.request_no,'service_type',r.service_type,'description',r.description,'status',r.status,'service_date',r.service_date,'start_time',r.start_time,'address',r.address,'assigned_worker',r.assigned_worker,'quote_amount',r.quote_amount,'current_actor',r.current_actor,'next_action',r.next_action,'updated_at',r.updated_at),
    'events',coalesce((select jsonb_agg(jsonb_build_object('action',e.action,'from_status',e.from_status,'to_status',e.to_status,'note',e.note,'created_at',e.created_at) order by e.created_at) from public.task_events e where e.request_no=v_no),'[]'::jsonb),
    'inspections',coalesce((select jsonb_agg(jsonb_build_object('type',i.inspection_type,'status',i.status,'result',i.result,'review_note',i.review_note,'created_at',i.created_at) order by i.created_at) from public.task_inspections i where i.request_no=v_no),'[]'::jsonb)
  );
end;$$;

create or replace function public.get_customer_milestone_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_no text:=upper(trim(p_request_no)); v_request public.service_requests%rowtype; v_inspection public.task_inspections%rowtype;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into v_request from public.service_requests r where r.request_no=v_no; if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  select * into v_inspection from public.task_inspections i where i.request_no=v_no and i.inspection_type='milestone' order by i.sequence_no desc limit 1; if not found then raise exception 'MILESTONE_NOT_FOUND'; end if;
  return jsonb_build_object('request_no',v_request.request_no,'status',v_request.status,'service_type',v_request.service_type,'description',v_request.description,'latest_work_progress',v_request.latest_work_progress,'latest_issues_found',v_request.latest_issues_found,'sequence_no',v_inspection.sequence_no,'inspection_status',v_inspection.status,'evidence_count',coalesce(jsonb_array_length(v_inspection.evidence),0),'submitted_at',v_inspection.created_at);
end;$$;
