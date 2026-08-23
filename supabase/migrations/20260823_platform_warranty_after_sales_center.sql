create table if not exists public.warranty_records (
  id uuid primary key default gen_random_uuid(),
  request_no text not null unique references public.service_requests(request_no) on update cascade,
  settlement_id bigint references public.order_settlements(id),
  customer_phone text,
  responsible_worker_phone text,
  status text not null default 'pending_terms' check (status in ('pending_terms','active','expired','suspended','closed')),
  warranty_start_at timestamptz,
  warranty_end_at timestamptz,
  coverage_scope text,
  exclusions text,
  response_hours integer check (response_hours between 1 and 720),
  approval_note text,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.after_sales_cases (
  id uuid primary key default gen_random_uuid(),
  case_no text not null unique default ('AS-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')),
  warranty_id uuid not null references public.warranty_records(id),
  request_no text not null references public.service_requests(request_no) on update cascade,
  issue_description text not null,
  customer_evidence text,
  severity text not null default 'normal' check (severity in ('normal','urgent','critical')),
  status text not null default 'open' check (status in ('open','in_review','repairing','awaiting_reinspection','closed','rejected')),
  responsible_worker_phone text,
  due_at timestamptz,
  platform_note text,
  reinspection_result text,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists after_sales_cases_warranty_status_idx on public.after_sales_cases(warranty_id,status);
create index if not exists after_sales_cases_due_idx on public.after_sales_cases(due_at) where status not in ('closed','rejected');
alter table public.warranty_records enable row level security;
alter table public.after_sales_cases enable row level security;
revoke all on public.warranty_records, public.after_sales_cases from anon, authenticated;

insert into public.warranty_records(request_no,settlement_id,customer_phone,responsible_worker_phone,warranty_start_at)
select s.request_no,s.id,s.customer_phone,s.worker_phone,s.archived_at
from public.order_settlements s
where s.status='archived' and s.archived_at is not null
on conflict(request_no) do nothing;

create or replace function public.ensure_warranty_after_settlement_archive()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.status='archived' and new.archived_at is not null then
    insert into public.warranty_records(request_no,settlement_id,customer_phone,responsible_worker_phone,warranty_start_at)
    values(new.request_no,new.id,new.customer_phone,new.worker_phone,new.archived_at)
    on conflict(request_no) do nothing;
  end if;
  return new;
end;$$;
drop trigger if exists trg_ensure_warranty_after_settlement_archive on public.order_settlements;
create trigger trg_ensure_warranty_after_settlement_archive after insert or update of status,archived_at on public.order_settlements
for each row execute function public.ensure_warranty_after_settlement_archive();

create or replace function public.get_platform_warranty_center_with_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'pending_terms',(select count(*) from public.warranty_records where status='pending_terms'),
      'active',(select count(*) from public.warranty_records where status='active' and warranty_end_at>now()),
      'open_cases',(select count(*) from public.after_sales_cases where status not in ('closed','rejected')),
      'overdue_cases',(select count(*) from public.after_sales_cases where status not in ('closed','rejected') and due_at<now())
    ),
    'warranties',coalesce((select jsonb_agg(jsonb_build_object(
      'id',w.id,'request_no',w.request_no,'service_type',r.service_type,'status',case when w.status='active' and w.warranty_end_at<=now() then 'expired' else w.status end,
      'customer_phone',w.customer_phone,'worker_phone',w.responsible_worker_phone,'start_at',w.warranty_start_at,'end_at',w.warranty_end_at,
      'scope',w.coverage_scope,'exclusions',w.exclusions,'response_hours',w.response_hours,'approval_note',w.approval_note,
      'open_cases',(select count(*) from public.after_sales_cases c where c.warranty_id=w.id and c.status not in ('closed','rejected')),
      'updated_at',w.updated_at
    ) order by case w.status when 'pending_terms' then 1 when 'active' then 2 else 3 end,w.updated_at desc) from public.warranty_records w join public.service_requests r on r.request_no=w.request_no),'[]'::jsonb),
    'cases',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'case_no',c.case_no,'request_no',c.request_no,'issue',c.issue_description,'evidence',c.customer_evidence,
      'severity',c.severity,'status',c.status,'worker_phone',c.responsible_worker_phone,'due_at',c.due_at,
      'platform_note',c.platform_note,'reinspection_result',c.reinspection_result,'opened_at',c.opened_at,'closed_at',c.closed_at
    ) order by case when c.status not in ('closed','rejected') then 0 else 1 end,c.opened_at desc) from public.after_sales_cases c),'[]'::jsonb)
  );
end;$$;

create or replace function public.activate_warranty_with_token(p_token text,p_warranty_id uuid,p_warranty_days integer,p_scope text,p_exclusions text,p_response_hours integer,p_note text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare w public.warranty_records;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if p_warranty_days is null or p_warranty_days<1 or p_warranty_days>3650 then raise exception 'INVALID_WARRANTY_DAYS'; end if;
  if nullif(trim(p_scope),'') is null or nullif(trim(p_exclusions),'') is null or p_response_hours is null or p_response_hours<1 or p_response_hours>720 or nullif(trim(p_note),'') is null then raise exception 'TERMS_AND_APPROVAL_NOTE_REQUIRED'; end if;
  update public.warranty_records set status='active',warranty_start_at=coalesce(warranty_start_at,now()),warranty_end_at=coalesce(warranty_start_at,now())+make_interval(days=>p_warranty_days),coverage_scope=trim(p_scope),exclusions=trim(p_exclusions),response_hours=p_response_hours,approval_note=trim(p_note),approved_at=now(),updated_at=now() where id=p_warranty_id returning * into w;
  if w.id is null then raise exception 'WARRANTY_NOT_FOUND'; end if;
  return jsonb_build_object('ok',true,'request_no',w.request_no,'status',w.status,'end_at',w.warranty_end_at);
end;$$;

create or replace function public.create_after_sales_case_with_token(p_token text,p_warranty_id uuid,p_issue text,p_evidence text,p_severity text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare w public.warranty_records; c public.after_sales_cases;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select * into w from public.warranty_records where id=p_warranty_id;
  if w.id is null then raise exception 'WARRANTY_NOT_FOUND'; end if;
  if w.status<>'active' or w.warranty_end_at<=now() then raise exception 'WARRANTY_NOT_ACTIVE'; end if;
  if nullif(trim(p_issue),'') is null then raise exception 'ISSUE_REQUIRED'; end if;
  if p_severity not in ('normal','urgent','critical') then raise exception 'INVALID_SEVERITY'; end if;
  insert into public.after_sales_cases(warranty_id,request_no,issue_description,customer_evidence,severity,responsible_worker_phone,due_at)
  values(w.id,w.request_no,trim(p_issue),nullif(trim(p_evidence),''),p_severity,w.responsible_worker_phone,now()+make_interval(hours=>w.response_hours)) returning * into c;
  return jsonb_build_object('ok',true,'case_no',c.case_no,'due_at',c.due_at);
end;$$;

create or replace function public.update_after_sales_case_with_token(p_token text,p_case_id uuid,p_action text,p_note text,p_reinspection_result text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare c public.after_sales_cases; new_status text;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if nullif(trim(p_note),'') is null then raise exception 'HUMAN_NOTE_REQUIRED'; end if;
  new_status:=case p_action when 'review' then 'in_review' when 'repair' then 'repairing' when 'reinspect' then 'awaiting_reinspection' when 'close' then 'closed' when 'reject' then 'rejected' else null end;
  if new_status is null then raise exception 'INVALID_ACTION'; end if;
  if p_action='close' and nullif(trim(p_reinspection_result),'') is null then raise exception 'REINSPECTION_RESULT_REQUIRED'; end if;
  update public.after_sales_cases set status=new_status,platform_note=trim(p_note),reinspection_result=case when p_reinspection_result is not null then trim(p_reinspection_result) else reinspection_result end,closed_at=case when new_status in ('closed','rejected') then now() else null end,updated_at=now() where id=p_case_id returning * into c;
  if c.id is null then raise exception 'CASE_NOT_FOUND'; end if;
  return jsonb_build_object('ok',true,'case_no',c.case_no,'status',c.status);
end;$$;

revoke all on function public.ensure_warranty_after_settlement_archive() from public,anon,authenticated;
grant execute on function public.ensure_warranty_after_settlement_archive() to service_role;
revoke all on function public.get_platform_warranty_center_with_token(text) from public;
revoke all on function public.activate_warranty_with_token(text,uuid,integer,text,text,integer,text) from public;
revoke all on function public.create_after_sales_case_with_token(text,uuid,text,text,text) from public;
revoke all on function public.update_after_sales_case_with_token(text,uuid,text,text,text) from public;
grant execute on function public.get_platform_warranty_center_with_token(text),public.activate_warranty_with_token(text,uuid,integer,text,text,integer,text),public.create_after_sales_case_with_token(text,uuid,text,text,text),public.update_after_sales_case_with_token(text,uuid,text,text,text) to anon,authenticated,service_role;
