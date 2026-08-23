begin;
create or replace function public.get_platform_overdue_alerts_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
 if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
 if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
 return jsonb_build_object('alerts',coalesce((select jsonb_agg(jsonb_build_object('request_no',r.request_no,'status',r.status,'updated_at',r.updated_at,'hours_waiting',floor(extract(epoch from(now()-r.updated_at))/3600)) order by r.updated_at) from public.service_requests r where (r.status in ('submitted','reviewed','quoted','confirmed','quote_confirmed') and r.updated_at<now()-interval '24 hours') or (r.status in ('assigned','accepted','arrived','working','in_progress') and r.updated_at<now()-interval '48 hours')),'[]'::jsonb));
end;$function$;
revoke all on function public.get_platform_overdue_alerts_with_token(text) from public,anon,authenticated;
grant execute on function public.get_platform_overdue_alerts_with_token(text) to anon,authenticated,service_role;
commit;
