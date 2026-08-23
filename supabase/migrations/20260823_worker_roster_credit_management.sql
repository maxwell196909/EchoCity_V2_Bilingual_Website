begin;

create table if not exists public.service_workers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  full_name text not null,
  phone text,
  city text,
  skills text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','active','paused','suspended')),
  verification_status text not null default 'unverified' check (verification_status in ('unverified','pending','verified','rejected')),
  availability_status text not null default 'offline' check (availability_status in ('available','busy','offline')),
  credit_score numeric(5,2) not null default 100 check (credit_score between 0 and 100),
  completed_orders integer not null default 0,
  rework_count integer not null default 0,
  dispute_count integer not null default 0,
  last_active_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists service_workers_phone_unique
  on public.service_workers(phone) where phone is not null and phone <> '';

create table if not exists public.worker_credit_events (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.service_workers(id) on delete cascade,
  request_no text,
  event_type text not null,
  score_delta numeric(5,2) not null default 0,
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  created_by text not null default 'platform',
  created_at timestamptz not null default now()
);

alter table public.service_workers enable row level security;
alter table public.worker_credit_events enable row level security;
revoke all on table public.service_workers from anon, authenticated;
revoke all on table public.worker_credit_events from anon, authenticated;

insert into public.service_workers(full_name,phone,status,verification_status,availability_status,last_active_at)
select max(coalesce(nullif(trim(r.assigned_worker),''),'未命名服务人员')),
       nullif(trim(r.assigned_worker_phone),''),
       'active','pending','offline',max(r.updated_at)
from public.service_requests r
where nullif(trim(r.assigned_worker_phone),'') is not null
group by trim(r.assigned_worker_phone)
on conflict (phone) where phone is not null and phone <> '' do update
set full_name=excluded.full_name,last_active_at=greatest(public.service_workers.last_active_at,excluded.last_active_at),updated_at=now();

update public.service_workers w set
  completed_orders=(select count(*) from public.service_requests r where r.assigned_worker_phone=w.phone and r.status in ('closed','completed','settled')),
  rework_count=(select count(*) from public.service_requests r where r.assigned_worker_phone=w.phone and (r.status in ('rework','disputed') or r.final_acceptance_status='rework')),
  dispute_count=(select count(*) from public.service_requests r where r.assigned_worker_phone=w.phone and r.status='disputed'),
  updated_at=now();

create or replace function public.get_platform_worker_roster_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'total',(select count(*) from public.service_workers),
      'active',(select count(*) from public.service_workers where status='active'),
      'available',(select count(*) from public.service_workers where availability_status='available'),
      'pending_verification',(select count(*) from public.service_workers where verification_status in ('unverified','pending'))
    ),
    'workers',coalesce((select jsonb_agg(jsonb_build_object(
      'id',w.id,'full_name',w.full_name,'phone',w.phone,'city',w.city,'skills',w.skills,
      'status',w.status,'verification_status',w.verification_status,'availability_status',w.availability_status,
      'credit_score',w.credit_score,'completed_orders',w.completed_orders,'rework_count',w.rework_count,
      'dispute_count',w.dispute_count,'last_active_at',w.last_active_at
    ) order by w.updated_at desc) from public.service_workers w),'[]'::jsonb)
  );
end;$function$;

create or replace function public.update_platform_worker_status_with_token(p_token text,p_worker_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_old text; v_name text;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if p_status not in ('pending','active','paused','suspended') then raise exception 'INVALID_WORKER_STATUS'; end if;
  select status,full_name into v_old,v_name from public.service_workers where id=p_worker_id for update;
  if not found then raise exception 'WORKER_NOT_FOUND'; end if;
  update public.service_workers set status=p_status,availability_status=case when p_status='active' then availability_status else 'offline' end,updated_at=now() where id=p_worker_id;
  insert into public.worker_credit_events(worker_id,event_type,score_delta,reason,evidence)
  values(p_worker_id,'status_changed',0,'平台调整服务人员状态',jsonb_build_object('from_status',v_old,'to_status',p_status));
  return jsonb_build_object('ok',true,'worker_id',p_worker_id,'full_name',v_name,'status',p_status);
end;$function$;

revoke all on function public.get_platform_worker_roster_with_token(text) from public,anon,authenticated;
revoke all on function public.update_platform_worker_status_with_token(text,uuid,text) from public,anon,authenticated;
grant execute on function public.get_platform_worker_roster_with_token(text) to anon,authenticated,service_role;
grant execute on function public.update_platform_worker_status_with_token(text,uuid,text) to anon,authenticated,service_role;

commit;
