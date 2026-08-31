create or replace function public.record_public_video_watch_v1(
  p_video_id uuid,
  p_session_id text,
  p_feed_type text default 'recommend',
  p_position integer default null,
  p_watch_ms integer default 0,
  p_video_duration_ms integer default null,
  p_completed boolean default false
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id bigint;
  v_user uuid := auth.uid();
  v_session text := nullif(trim(coalesce(p_session_id,'')),'');
  v_feed text := lower(trim(coalesce(p_feed_type,'recommend')));
  v_watch integer := greatest(0,least(coalesce(p_watch_ms,0),21600000));
  v_duration integer := case when p_video_duration_ms is null then null else greatest(1,least(p_video_duration_ms,21600000)) end;
begin
  if p_video_id is null then raise exception 'INVALID_VIDEO'; end if;
  if v_session is null or length(v_session) > 120 then raise exception 'INVALID_SESSION'; end if;
  if v_feed not in ('recommend','local','following','hot','shared') then v_feed := 'recommend'; end if;
  if p_position is not null and (p_position < 0 or p_position > 10000) then raise exception 'INVALID_POSITION'; end if;
  if not exists (
    select 1 from public.videos v
    where v.id=p_video_id and v.status='published' and v.visibility='public'
  ) then raise exception 'VIDEO_NOT_PUBLIC'; end if;

  insert into public.feed_impressions(
    user_id,video_id,feed_type,session_id,position,watch_ms,video_duration_ms,completed,shown_at,ended_at,metadata
  ) values(
    v_user,p_video_id,v_feed,v_session,p_position,v_watch,v_duration,
    coalesce(p_completed,false),now()-make_interval(secs => (v_watch::numeric/1000.0)),now(),
    jsonb_build_object('record_channel','public_watch_rpc','anonymous',v_user is null)
  ) returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.record_public_video_watch_v1(uuid,text,text,integer,integer,integer,boolean) from public;
grant execute on function public.record_public_video_watch_v1(uuid,text,text,integer,integer,integer,boolean) to anon, authenticated, service_role;
