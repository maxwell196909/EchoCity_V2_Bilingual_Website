create or replace function public.record_public_video_conversion_v1(
  p_video_id uuid,
  p_conversion_type text,
  p_session_id text default null,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_type text := lower(trim(coalesce(p_conversion_type,'')));
  v_session text := left(trim(coalesce(p_session_id,'')),128);
  v_meta jsonb := coalesce(p_metadata,'{}'::jsonb);
begin
  if v_type not in ('ai_consult','service_click') then
    raise exception 'INVALID_CONVERSION_TYPE';
  end if;

  if not exists (
    select 1 from public.videos v
    where v.id=p_video_id and v.status='published' and v.visibility='public'
  ) then
    raise exception 'VIDEO_NOT_PUBLIC';
  end if;

  v_meta := v_meta || jsonb_build_object(
    'session_id',nullif(v_session,''),
    'recorded_via','public_rpc'
  );

  insert into public.video_conversions(video_id,user_id,conversion_type,metadata)
  values (p_video_id,auth.uid(),v_type,v_meta)
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function public.record_public_video_conversion_v1(uuid,text,text,jsonb) from public;
grant execute on function public.record_public_video_conversion_v1(uuid,text,text,jsonb) to anon,authenticated,service_role;
