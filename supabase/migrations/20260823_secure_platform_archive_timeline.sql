begin;
create or replace function public.get_platform_archive_timeline_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
declare v_request public.service_requests%rowtype;
begin
 if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
 if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
 select * into v_request from public.service_requests r where r.request_no=upper(trim(p_request_no)); if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
 return jsonb_build_object('request',jsonb_build_object('request_no',v_request.request_no,'service_type',v_request.service_type,'description',v_request.description,'status',v_request.status,'customer_name',v_request.customer_name,'assigned_worker',v_request.assigned_worker,'quote_amount',v_request.quote_amount,'service_date',v_request.service_date,'address',v_request.address,'updated_at',v_request.updated_at),'events',coalesce((select jsonb_agg(jsonb_build_object('event_type',e.event_type,'action',e.action,'actor_role',e.actor_role,'from_status',e.from_status,'to_status',e.to_status,'note',e.note,'created_at',e.created_at) order by e.created_at) from public.task_events e where e.request_no=v_request.request_no),'[]'::jsonb),'inspections',coalesce((select jsonb_agg(jsonb_build_object('type',i.inspection_type,'sequence',i.sequence_no,'status',i.status,'result',i.result,'review_note',i.review_note,'created_at',i.created_at) order by i.created_at) from public.task_inspections i where i.request_no=v_request.request_no),'[]'::jsonb),'settlement',(select jsonb_build_object('final_amount',s.final_amount,'status',s.status,'approved_at',s.approved_at) from public.task_settlements s where s.request_no=v_request.request_no order by s.updated_at desc limit 1),'rating',(select jsonb_build_object('rating',r.rating,'comment',r.comment,'created_at',r.created_at) from public.task_ratings r where r.request_no=v_request.request_no order by r.created_at desc limit 1));
end;$function$;
revoke all on function public.get_platform_archive_timeline_with_token(text,text) from public,anon,authenticated;
grant execute on function public.get_platform_archive_timeline_with_token(text,text) to anon,authenticated,service_role;
commit;
