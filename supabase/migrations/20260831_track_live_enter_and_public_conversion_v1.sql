create or replace function public.record_live_presence_v1(p_room_id uuid, p_session_id text, p_action text default 'heartbeat'::text)
returns table(viewer_count integer, peak_viewers integer)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_me uuid := auth.uid();
  v_count integer;
  v_peak integer;
  v_action text := lower(trim(coalesce(p_action,'heartbeat')));
  v_session text := trim(coalesce(p_session_id,''));
begin
  if p_room_id is null or char_length(v_session) not between 8 and 100 then raise exception 'INVALID_PRESENCE'; end if;
  if v_action not in ('enter','heartbeat','leave') then raise exception 'INVALID_ACTION'; end if;

  if not exists(select 1 from public.live_rooms r where r.id=p_room_id and r.status='live') then
    select coalesce(r.viewer_count,0),coalesce(r.peak_viewers,0) into v_count,v_peak from public.live_rooms r where r.id=p_room_id;
    return query select coalesce(v_count,0),coalesce(v_peak,0); return;
  end if;

  if v_action='leave' then
    delete from public.live_presence where room_id=p_room_id and session_id=v_session;
  else
    insert into public.live_presence(room_id,session_id,user_id,last_seen_at)
    values(p_room_id,v_session,v_me,now())
    on conflict(room_id,session_id) do update set user_id=excluded.user_id,last_seen_at=excluded.last_seen_at;

    if v_action='enter' and not exists (
      select 1 from public.live_view_events e
      where e.room_id=p_room_id and e.session_id=v_session and e.event_type='enter'
    ) then
      insert into public.live_view_events(room_id,user_id,session_id,event_type,metadata)
      values(p_room_id,v_me,v_session,'enter',jsonb_build_object('source','presence_v1'));
    end if;
  end if;

  delete from public.live_presence where room_id=p_room_id and last_seen_at < now()-interval '45 seconds';
  select count(*)::integer into v_count from public.live_presence where room_id=p_room_id and last_seen_at >= now()-interval '45 seconds';
  update public.live_rooms r set viewer_count=v_count,peak_viewers=greatest(coalesce(r.peak_viewers,0),v_count),updated_at=now() where r.id=p_room_id returning r.peak_viewers into v_peak;
  return query select v_count,coalesce(v_peak,v_count);
end
$function$;
revoke all on function public.record_live_presence_v1(uuid,text,text) from public;
grant execute on function public.record_live_presence_v1(uuid,text,text) to anon,authenticated,service_role;

create or replace function public.record_public_live_conversion_v1(p_room_id uuid,p_event_type text,p_session_id text default null,p_metadata jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_me uuid := auth.uid();
  v_event text := lower(trim(coalesce(p_event_type,'')));
  v_session text := nullif(trim(coalesce(p_session_id,'')),'');
  v_id bigint;
begin
  if p_room_id is null then raise exception 'INVALID_ROOM'; end if;
  if v_event not in ('ai_consult','service_click') then raise exception 'INVALID_EVENT_TYPE'; end if;
  if v_session is not null and char_length(v_session) > 100 then raise exception 'INVALID_SESSION'; end if;
  if not exists(select 1 from public.live_rooms r where r.id=p_room_id and r.status in ('live','ended')) then raise exception 'ROOM_NOT_AVAILABLE'; end if;
  if v_session is not null then
    select e.id into v_id from public.live_view_events e where e.room_id=p_room_id and e.session_id=v_session and e.event_type=v_event order by e.id desc limit 1;
    if v_id is not null then return v_id; end if;
  end if;
  insert into public.live_view_events(room_id,user_id,session_id,event_type,metadata)
  values(p_room_id,v_me,v_session,v_event,coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object('source','public_live_conversion_v1'))
  returning id into v_id;
  return v_id;
end
$function$;
revoke all on function public.record_public_live_conversion_v1(uuid,text,text,jsonb) from public;
grant execute on function public.record_public_live_conversion_v1(uuid,text,text,jsonb) to anon,authenticated,service_role;
