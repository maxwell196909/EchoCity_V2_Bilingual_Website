-- Secure customer order-progress access with the shared customer task token.

create or replace function public.get_customer_progress_timeline_with_token(
  p_request_no text,
  p_token text
)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_no text:=upper(trim(p_request_no));
  r public.service_requests;
begin
  if p_token is null or length(p_token)<>64
     or not public.validate_task_access_token(v_no,'customer',p_token) then
    raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID';
  end if;

  select * into r
  from public.service_requests
  where request_no=v_no;

  if not found then
    raise exception 'REQUEST_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'request',jsonb_build_object(
      'request_no',r.request_no,
      'service_type',r.service_type,
      'description',r.description,
      'status',r.status,
      'service_date',r.service_date,
      'start_time',r.start_time,
      'address',r.address,
      'assigned_worker',r.assigned_worker,
      'quote_amount',r.quote_amount,
      'current_actor',r.current_actor,
      'next_action',r.next_action,
      'updated_at',r.updated_at
    ),
    'events',coalesce((
      select jsonb_agg(jsonb_build_object(
        'action',e.action,
        'from_status',e.from_status,
        'to_status',e.to_status,
        'note',e.note,
        'created_at',e.created_at
      ) order by e.created_at)
      from public.task_events e
      where e.request_no=v_no
    ),'[]'::jsonb),
    'inspections',coalesce((
      select jsonb_agg(jsonb_build_object(
        'type',i.inspection_type,
        'status',i.status,
        'result',i.result,
        'review_note',i.review_note,
        'created_at',i.created_at
      ) order by i.created_at)
      from public.task_inspections i
      where i.request_no=v_no
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_customer_progress_timeline_with_token(text,text) from public;
grant execute on function public.get_customer_progress_timeline_with_token(text,text) to anon,authenticated,service_role;

-- Legacy phone-based full-detail functions are retained only for server-side compatibility.
revoke all on function public.get_customer_progress_timeline(text,text) from public,anon,authenticated;
grant execute on function public.get_customer_progress_timeline(text,text) to service_role;

revoke all on function public.get_customer_quote_with_phone(text,text) from public,anon,authenticated;
grant execute on function public.get_customer_quote_with_phone(text,text) to service_role;

-- Keep phone + request-number lookup as a low-sensitivity discovery surface only.
create or replace function public.lookup_customer_request(
  p_request_no text,
  p_customer_phone text
)
returns table(
  request_no text,
  service_type text,
  description text,
  service_date date,
  start_time time without time zone,
  workers integer,
  duration text,
  address text,
  status text,
  quote_amount numeric,
  assigned_worker text
)
language sql
stable security definer
set search_path=''
as $$
  select request.request_no,
    request.service_type,
    null::text as description,
    request.service_date,
    null::time as start_time,
    null::integer as workers,
    null::text as duration,
    null::text as address,
    request.status,
    case when request.status in ('quoted','quote_confirmed','quote_declined')
      then request.quote_amount else null end,
    null::text as assigned_worker
  from public.service_requests request
  where request.request_no=upper(trim(p_request_no))
    and regexp_replace(coalesce(request.customer_phone,''),'[^0-9]','','g')=
        regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')
    and length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) between 7 and 20
    and length(trim(coalesce(p_request_no,''))) between 8 and 80
  limit 1;
$$;

revoke all on function public.lookup_customer_request(text,text) from public;
grant execute on function public.lookup_customer_request(text,text) to anon,authenticated,service_role;
