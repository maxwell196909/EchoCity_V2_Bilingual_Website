create or replace function public.get_recommended_videos_v1(p_limit integer default 30, p_city text default null)
returns table(video_id uuid, author_id uuid, title text, description text, video_url text, cover_url text, city text, published_at timestamptz, score numeric)
language sql
stable
security definer
set search_path to ''
as $function$
with eligible as (
  select v.id, v.author_id, v.title, v.description, v.video_url, v.cover_url, v.city, v.published_at
  from public.videos v
  where v.status = 'published'
    and v.visibility = 'public'
    and (p_city is null or v.city = p_city)
),
imp as (
  select fi.video_id,
    count(*)::numeric as impressions,
    coalesce(avg(case when fi.video_duration_ms > 0 then least(fi.watch_ms::numeric / fi.video_duration_ms, 1) end),0)::numeric as completion_rate,
    count(*) filter (where fi.completed)::numeric as completed_views
  from public.feed_impressions fi
  join eligible e on e.id = fi.video_id
  where fi.shown_at >= now() - interval '30 days'
  group by fi.video_id
),
inter as (
  select vi.video_id,
    count(*) filter (where vi.action='like')::numeric as likes,
    count(*) filter (where vi.action='favorite')::numeric as favorites,
    count(*) filter (where vi.action='share')::numeric as shares
  from public.video_interactions vi
  join eligible e on e.id = vi.video_id
  where vi.created_at >= now() - interval '30 days'
  group by vi.video_id
),
conv as (
  select vc.video_id,
    count(*) filter (where vc.conversion_type='ai_consult')::numeric as ai_consults,
    count(*) filter (where vc.conversion_type='service_click')::numeric as service_clicks,
    count(*) filter (where vc.conversion_type='request_created')::numeric as request_events
  from public.video_conversions vc
  join eligible e on e.id = vc.video_id
  where vc.created_at >= now() - interval '30 days'
  group by vc.video_id
),
biz as (
  select sr.source_video_id as video_id,
    count(*)::numeric as requests,
    count(*) filter (where sr.quote_amount is not null)::numeric as quoted,
    count(*) filter (where coalesce(sr.quote_confirmed,false))::numeric as confirmed,
    count(*) filter (where sr.work_completed_at is not null or sr.status='completed')::numeric as completed,
    coalesce(sum(sr.quote_amount) filter (where coalesce(sr.quote_confirmed,false)),0)::numeric as confirmed_amount,
    coalesce(sum(sr.quote_amount) filter (where sr.work_completed_at is not null or sr.status='completed'),0)::numeric as completed_amount
  from public.service_requests sr
  join eligible e on e.id = sr.source_video_id
  where sr.created_at >= now() - interval '30 days'
    and sr.source_video_id is not null
  group by sr.source_video_id
),
scored as (
  select e.*,
    coalesce(i.impressions,0) as impressions,
    coalesce(i.completion_rate,0) as completion_rate,
    coalesce(x.likes,0) as likes,
    coalesce(x.favorites,0) as favorites,
    coalesce(x.shares,0) as shares,
    coalesce(c.ai_consults,0) as ai_consults,
    coalesce(c.service_clicks,0) as service_clicks,
    greatest(coalesce(c.request_events,0),coalesce(b.requests,0)) as requests,
    coalesce(b.confirmed,0) as confirmed,
    coalesce(b.completed,0) as completed,
    coalesce(b.completed_amount,0) as completed_amount
  from eligible e
  left join imp i on i.video_id=e.id
  left join inter x on x.video_id=e.id
  left join conv c on c.video_id=e.id
  left join biz b on b.video_id=e.id
)
select s.id, s.author_id, s.title, s.description, s.video_url, s.cover_url, s.city, s.published_at,
  (
    s.completion_rate * 24
    + ln(1+s.impressions) * 2
    + ln(1+s.likes) * 6
    + ln(1+s.favorites) * 7
    + ln(1+s.shares) * 8
    + least(30::numeric,
        (ln(1+s.ai_consults)*3
         + ln(1+s.service_clicks)*4
         + ln(1+s.requests)*7
         + ln(1+s.confirmed)*10
         + ln(1+s.completed)*12
         + ln(1+(s.completed_amount/100.0))*2)
        * (0.5 + 0.5*s.completion_rate)
      )
    + greatest(0::numeric, 8 - extract(epoch from (now()-coalesce(s.published_at,now())))/86400)
  )::numeric as score
from scored s
order by score desc, s.published_at desc nulls last
limit greatest(1,least(coalesce(p_limit,30),100));
$function$;
revoke all on function public.get_recommended_videos_v1(integer,text) from public;
grant execute on function public.get_recommended_videos_v1(integer,text) to anon, authenticated, service_role;
