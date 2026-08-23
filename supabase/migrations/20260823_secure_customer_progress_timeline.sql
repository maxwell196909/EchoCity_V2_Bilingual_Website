begin;
create or replace function public.get_customer_progress_timeline(p_request_no text,p_customer_phone text)
returns jsonb language sql security definer stable set search_path='' as $function$
 select jsonb_build_object(
  'request',jsonb_build_object('request_no',r.request_no,'service_type',r.service_type,'description',r.description,'status',r.status,'service_date',r.service_date,'start_time',r.start_time,'address',r.address,'assigned_worker',r.assigned_worker,'quote_amount',r.quote_amount,'updated_at',r.updated_at),
  'events',coalesce((select jsonb_agg(jsonb_build_object('action',e.action,'from_status',e.from_status,'to_status',e.to_status,'note',e.note,'created_at',e.created_at) order by e.created_at) from public.task_events e where e.request_no=r.request_no),'[]'::jsonb),
  'inspections',coalesce((select jsonb_agg(jsonb_build_object('type',i.inspection_type,'status',i.status,'result',i.result,'review_note',i.review_note,'created_at',i.created_at) order by i.created_at) from public.task_inspections i where i.request_no=r.request_no),'[]'::jsonb)
 ) from public.service_requests r
 where r.request_no=upper(trim(p_request_no))
 and regexp_replace(coalesce(r.customer_phone,''),'[^0-9]','','g')=regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')
 and length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) between 7 and 20 limit 1;
$function$;
revoke all on function public.get_customer_progress_timeline(text,text) from public,anon,authenticated;
grant execute on function public.get_customer_progress_timeline(text,text) to anon,authenticated,service_role;
commit;
