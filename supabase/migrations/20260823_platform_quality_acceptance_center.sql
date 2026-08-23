begin;

create or replace function public.get_platform_quality_center_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'platform_milestone_review',(select count(*) from public.service_requests where status='milestone_customer_approved'),
      'customer_final_acceptance',(select count(*) from public.service_requests where status='awaiting_final_acceptance'),
      'rework_or_dispute',(select count(*) from public.service_requests where status in ('rework','disputed')),
      'evidence_incomplete',(select count(*) from public.service_requests r where r.status in ('milestone_customer_approved','awaiting_final_acceptance') and ((select count(*) from public.work_records w where w.request_no=r.request_no)=0 or not exists(select 1 from public.work_records w where w.request_no=r.request_no and w.photo_record is not null and trim(w.photo_record)<>'')))
    ),
    'orders',coalesce((select jsonb_agg(jsonb_build_object(
      'request_no',r.request_no,'service_type',r.service_type,'status',r.status,'worker',r.assigned_worker,
      'work_record_count',(select count(*) from public.work_records w where w.request_no=r.request_no),
      'work_hours',(select coalesce(sum(w.work_hours),0) from public.work_records w where w.request_no=r.request_no),
      'photo_record_count',(select count(*) from public.work_records w where w.request_no=r.request_no and w.photo_record is not null and trim(w.photo_record)<>''),
      'video_record_count',(select count(*) from public.work_records w where w.request_no=r.request_no and w.video_record is not null and trim(w.video_record)<>''),
      'milestone_summary',r.milestone_summary,'milestone_evidence',r.milestone_evidence,
      'milestone_submitted_at',r.milestone_submitted_at,'work_completed_at',r.work_completed_at,
      'final_acceptance_status',r.final_acceptance_status,'final_rating',r.final_acceptance_data->>'final_rating',
      'outstanding_issues',coalesce(r.outstanding_issues,r.latest_issues_found),
      'queue',case when r.status='milestone_customer_approved' then 'platform_review' when r.status='awaiting_final_acceptance' then 'customer_final' when r.status='rework' then 'rework' else 'dispute' end,
      'updated_at',r.updated_at
    ) order by case when r.status='milestone_customer_approved' then 1 when r.status='awaiting_final_acceptance' then 2 else 3 end,r.updated_at)
    from public.service_requests r where r.status in ('milestone_customer_approved','awaiting_final_acceptance','rework','disputed')),'[]'::jsonb)
  );
end;$function$;

revoke all on function public.get_platform_quality_center_with_token(text) from public,anon,authenticated;
grant execute on function public.get_platform_quality_center_with_token(text) to anon,authenticated,service_role;

commit;
