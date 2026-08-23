begin;
create or replace function public.get_platform_operations_summary_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
 if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
 if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
 return jsonb_build_object(
  'total',(select count(*) from public.service_requests),
  'pending_review',(select count(*) from public.service_requests where status in ('submitted','reviewed')),
  'pending_quote_confirmation',(select count(*) from public.service_requests where status='quoted'),
  'pending_assignment',(select count(*) from public.service_requests where status in ('confirmed','quote_confirmed')),
  'active',(select count(*) from public.service_requests where status in ('assigned','accepted','arrived','agreement_submitted','working','in_progress','milestone_submitted','milestone_approved')),
  'pending_final_acceptance',(select count(*) from public.service_requests where status in ('awaiting_final_acceptance','waiting_final_acceptance')),
  'disputed',(select count(*) from public.service_requests where status in ('final_rework','disputed')),
  'closed',(select count(*) from public.service_requests where status in ('completed','closed','archived')),
  'recent',coalesce((select jsonb_agg(jsonb_build_object('request_no',x.request_no,'status',x.status,'service_type',x.service_type,'updated_at',x.updated_at) order by x.updated_at desc) from (select request_no,status,service_type,updated_at from public.service_requests order by updated_at desc limit 10)x),'[]'::jsonb)
 );
end;$function$;
revoke all on function public.get_platform_operations_summary_with_token(text) from public,anon,authenticated;
grant execute on function public.get_platform_operations_summary_with_token(text) to anon,authenticated,service_role;
commit;
