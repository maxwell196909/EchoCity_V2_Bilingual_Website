begin;

create or replace function public.submit_customer_service_request(
  p_service_type text,
  p_description text,
  p_service_date date,
  p_start_time time,
  p_workers integer,
  p_duration text,
  p_postal_code text,
  p_address text,
  p_customer_name text,
  p_customer_phone text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_request_no text; v_row public.service_requests%rowtype;
begin
  if length(trim(coalesce(p_service_type,''))) not between 2 and 100 then raise exception 'INVALID_SERVICE_TYPE'; end if;
  if length(trim(coalesce(p_description,''))) not between 2 and 4000 then raise exception 'INVALID_DESCRIPTION'; end if;
  if length(regexp_replace(coalesce(p_customer_phone,''),'\D','','g')) not between 7 and 20 then raise exception 'INVALID_CUSTOMER_PHONE'; end if;
  if length(trim(coalesce(p_customer_name,''))) not between 1 and 120 then raise exception 'INVALID_CUSTOMER_NAME'; end if;
  if coalesce(p_workers,1) not between 1 and 100 then raise exception 'INVALID_WORKER_COUNT'; end if;
  if length(coalesce(p_address,''))>500 or length(coalesce(p_duration,''))>100 or length(coalesce(p_postal_code,''))>30 then raise exception 'FIELD_TOO_LONG'; end if;

  v_request_no := 'REQ-' || floor(extract(epoch from clock_timestamp())*1000)::bigint::text;
  insert into public.service_requests(
    request_no,service_type,description,service_date,start_time,workers,duration,
    postal_code,address,customer_name,customer_phone,status,current_actor,next_action,
    intake_channel,workflow_stage,updated_at
  ) values(
    v_request_no,trim(p_service_type),trim(p_description),p_service_date,p_start_time,
    coalesce(p_workers,1),nullif(trim(coalesce(p_duration,'')),''),nullif(trim(coalesce(p_postal_code,'')),''),
    nullif(trim(coalesce(p_address,'')),''),trim(p_customer_name),trim(p_customer_phone),
    'submitted','platform','prepare_quote','web','intake',now()
  ) returning * into v_row;

  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence)
  values(v_request_no,'request_intake','customer_submitted_request','customer',null,'submitted','客户网页提交服务需求',jsonb_build_object('channel','web'));

  return jsonb_build_object('request_no',v_row.request_no,'status',v_row.status,'created_at',v_row.created_at);
end;$function$;

revoke all on function public.submit_customer_service_request(text,text,date,time,integer,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.submit_customer_service_request(text,text,date,time,integer,text,text,text,text,text) to anon,authenticated,service_role;

commit;
