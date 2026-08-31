create or replace function public.review_platform_video_with_token(
  p_token text,
  p_video_id uuid,
  p_decision text,
  p_note text default null
)
returns table(video_id uuid, new_status text, published_at timestamptz)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
begin
  if p_token is null or length(p_token) < 64 or length(p_token) > 128 then
    raise exception 'INVALID_PLATFORM_LINK';
  end if;
  if not exists (
    select 1 from private.platform_dashboard_tokens t
    where t.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and t.revoked_at is null
      and t.expires_at > now()
  ) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;

  if p_decision not in ('approve','reject','hide') then
    raise exception 'INVALID_REVIEW_DECISION';
  end if;

  v_status := case p_decision
    when 'approve' then 'published'
    when 'reject' then 'rejected'
    else 'hidden'
  end;

  update public.videos as v
  set status = v_status,
      published_at = case
        when p_decision='approve' then coalesce(v.published_at, now())
        else v.published_at
      end,
      updated_at = now(),
      metadata = coalesce(v.metadata,'{}'::jsonb) || jsonb_build_object(
        'moderation_note', coalesce(p_note,''),
        'moderation_decision', p_decision,
        'moderated_at', now()
      )
  where v.id = p_video_id;

  if not found then raise exception 'VIDEO_NOT_FOUND'; end if;

  return query
  select v.id, v.status, v.published_at
  from public.videos v
  where v.id = p_video_id;
end;
$function$;
revoke all on function public.review_platform_video_with_token(text,uuid,text,text) from public;
grant execute on function public.review_platform_video_with_token(text,uuid,text,text) to anon, authenticated, service_role;
