create table if not exists public.after_sales_events (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.after_sales_cases(id),
  request_no text not null references public.service_requests(request_no) on update cascade,
  actor_role text not null check(actor_role in ('customer','platform','worker','system')),
  action text not null,
  from_status text,
  to_status text,
  note text,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists after_sales_events_case_created_idx on public.after_sales_events(case_id,created_at);
alter table public.after_sales_events enable row level security;
revoke all on public.after_sales_events from anon,authenticated;

create or replace function public.issue_customer_warranty_link_with_token(p_platform_token text,p_request_no text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_token text; v_request_no text:=upper(trim(p_request_no));
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if not exists(select 1 from public.warranty_records w where w.request_no=v_request_no) then raise exception 'WARRANTY_NOT_FOUND'; end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at,revoked_at)
  values(v_request_no,'customer',encode(extensions.digest(v_token,'sha256'),'hex'),now()+interval '30 days',null)
  on conflict(request_no,role) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,revoked_at=null;
  return jsonb_build_object('request_no',v_request_no,'customer_token',v_token,'expires_at',now()+interval '30 days');
end;$$;

create or replace function public.get_customer_warranty_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); w public.warranty_records; r public.service_requests;
begin
  if p_token is null or length(p_token)<>64 then raise exception 'INVALID_CUSTOMER_LINK'; end if;
  if not public.validate_task_access_token(v_request_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into w from public.warranty_records where request_no=v_request_no;
  if w.id is null then raise exception 'WARRANTY_NOT_FOUND'; end if;
  select * into r from public.service_requests where request_no=v_request_no;
  return jsonb_build_object(
    'warranty',jsonb_build_object('request_no',w.request_no,'service_type',r.service_type,'status',case when w.status='active' and w.warranty_end_at<=now() then 'expired' else w.status end,'start_at',w.warranty_start_at,'end_at',w.warranty_end_at,'scope',w.coverage_scope,'exclusions',w.exclusions,'response_hours',w.response_hours),
    'cases',coalesce((select jsonb_agg(jsonb_build_object('case_no',c.case_no,'issue',c.issue_description,'evidence',c.customer_evidence,'severity',c.severity,'status',c.status,'due_at',c.due_at,'platform_note',c.platform_note,'reinspection_result',c.reinspection_result,'opened_at',c.opened_at,'closed_at',c.closed_at) order by c.opened_at desc) from public.after_sales_cases c where c.warranty_id=w.id),'[]'::jsonb)
  );
end;$$;

create or replace function public.submit_customer_after_sales_with_token(p_request_no text,p_token text,p_issue text,p_evidence_note text,p_severity text,p_customer_confirmed boolean)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); w public.warranty_records; c public.after_sales_cases;
begin
  if p_token is null or length(p_token)<>64 then raise exception 'INVALID_CUSTOMER_LINK'; end if;
  if not public.validate_task_access_token(v_request_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into w from public.warranty_records where request_no=v_request_no;
  if w.id is null or w.status<>'active' or w.warranty_end_at<=now() then raise exception 'WARRANTY_NOT_ACTIVE'; end if;
  if p_customer_confirmed is not true then raise exception 'CUSTOMER_CONFIRMATION_REQUIRED'; end if;
  if nullif(trim(p_issue),'') is null or length(trim(p_issue))<5 or length(trim(p_issue))>2000 then raise exception 'ISSUE_DESCRIPTION_INVALID'; end if;
  if p_severity not in ('normal','urgent','critical') then raise exception 'INVALID_SEVERITY'; end if;
  insert into public.after_sales_cases(warranty_id,request_no,issue_description,customer_evidence,severity,responsible_worker_phone,due_at)
  values(w.id,w.request_no,trim(p_issue),nullif(trim(p_evidence_note),''),p_severity,w.responsible_worker_phone,now()+make_interval(hours=>w.response_hours)) returning * into c;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,to_status,note,evidence)
  values(c.id,c.request_no,'customer','submit','open','客户已确认问题描述',jsonb_build_object('evidence_note',coalesce(nullif(trim(p_evidence_note),''),''),'severity',p_severity));
  return jsonb_build_object('ok',true,'case_no',c.case_no,'status',c.status,'due_at',c.due_at);
end;$$;

create or replace function public.audit_after_sales_case_update()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
  if old.status is distinct from new.status then
    insert into public.after_sales_events(case_id,request_no,actor_role,action,from_status,to_status,note,evidence)
    values(new.id,new.request_no,'platform','status_update',old.status,new.status,new.platform_note,jsonb_build_object('reinspection_result',coalesce(new.reinspection_result,'')));
  end if;
  return new;
end;$$;
drop trigger if exists trg_audit_after_sales_case_update on public.after_sales_cases;
create trigger trg_audit_after_sales_case_update after update of status on public.after_sales_cases for each row execute function public.audit_after_sales_case_update();

revoke all on function public.issue_customer_warranty_link_with_token(text,text),public.get_customer_warranty_with_token(text,text),public.submit_customer_after_sales_with_token(text,text,text,text,text,boolean),public.audit_after_sales_case_update() from public;
revoke all on function public.audit_after_sales_case_update() from anon,authenticated;
grant execute on function public.audit_after_sales_case_update() to service_role;
grant execute on function public.issue_customer_warranty_link_with_token(text,text),public.get_customer_warranty_with_token(text,text),public.submit_customer_after_sales_with_token(text,text,text,text,text,boolean) to anon,authenticated,service_role;
