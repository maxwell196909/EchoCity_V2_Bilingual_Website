update storage.buckets set public=false,file_size_limit=104857600 where id='work-evidence';

create table if not exists public.after_sales_evidence (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.after_sales_cases(id),
  request_no text not null references public.service_requests(request_no) on update cascade,
  bucket_id text not null default 'work-evidence',
  storage_path text not null unique,
  original_file_name text not null,
  mime_type text not null,
  file_size bigint not null,
  uploaded_by_role text not null default 'customer' check(uploaded_by_role in ('customer','platform','worker')),
  review_status text not null default 'pending_review' check(review_status in ('pending_review','accepted','rejected')),
  object_version text,
  uploaded_at timestamptz not null default now(),
  reviewed_at timestamptz,
  review_note text
);
create index if not exists after_sales_evidence_case_idx on public.after_sales_evidence(case_id,uploaded_at);
alter table public.after_sales_evidence enable row level security;
revoke all on public.after_sales_evidence from anon,authenticated;

create or replace function public.commit_customer_after_sales_evidence_with_token(p_request_no text,p_token text,p_case_no text,p_storage_path text,p_file_name text,p_file_size bigint,p_mime_type text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); c public.after_sales_cases; obj storage.objects; e public.after_sales_evidence;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_request_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into c from public.after_sales_cases where case_no=p_case_no and request_no=v_request_no;
  if c.id is null then raise exception 'AFTER_SALES_CASE_NOT_FOUND'; end if;
  if c.status in ('closed','rejected') then raise exception 'CASE_NOT_OPEN_FOR_EVIDENCE'; end if;
  if p_storage_path not like v_request_no||'/customer/after-sales/'||p_case_no||'/%' then raise exception 'INVALID_EVIDENCE_PATH'; end if;
  if p_mime_type in ('image/jpeg','image/png','image/heic') and p_file_size between 1 and 15728640 then null;
  elsif p_mime_type in ('video/mp4','video/quicktime') and p_file_size between 1 and 104857600 then null;
  else raise exception 'INVALID_EVIDENCE_FILE'; end if;
  select * into obj from storage.objects where bucket_id='work-evidence' and name=p_storage_path;
  if obj.id is null then raise exception 'UPLOADED_OBJECT_NOT_FOUND'; end if;
  insert into public.after_sales_evidence(case_id,request_no,storage_path,original_file_name,mime_type,file_size,object_version)
  values(c.id,v_request_no,p_storage_path,left(p_file_name,180),p_mime_type,p_file_size,obj.version::text)
  returning * into e;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,from_status,to_status,note,evidence)
  values(c.id,v_request_no,'customer','evidence_uploaded',c.status,c.status,'客户上传售后证据',jsonb_build_object('evidence_id',e.id,'mime_type',e.mime_type,'file_size',e.file_size));
  return jsonb_build_object('ok',true,'evidence_id',e.id,'review_status',e.review_status);
end;$$;

create or replace function public.review_after_sales_evidence_with_token(p_platform_token text,p_evidence_id uuid,p_decision text,p_note text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare e public.after_sales_evidence;
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if p_decision not in ('accepted','rejected') or nullif(trim(p_note),'') is null then raise exception 'DECISION_AND_NOTE_REQUIRED'; end if;
  update public.after_sales_evidence set review_status=p_decision,reviewed_at=now(),review_note=trim(p_note) where id=p_evidence_id returning * into e;
  if e.id is null then raise exception 'EVIDENCE_NOT_FOUND'; end if;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,note,evidence)
  values(e.case_id,e.request_no,'platform','evidence_review',trim(p_note),jsonb_build_object('evidence_id',e.id,'decision',p_decision));
  return jsonb_build_object('ok',true,'evidence_id',e.id,'review_status',e.review_status);
end;$$;

revoke all on function public.commit_customer_after_sales_evidence_with_token(text,text,text,text,text,bigint,text),public.review_after_sales_evidence_with_token(text,uuid,text,text) from public;
grant execute on function public.commit_customer_after_sales_evidence_with_token(text,text,text,text,text,bigint,text),public.review_after_sales_evidence_with_token(text,uuid,text,text) to anon,authenticated,service_role;

create or replace function public.get_customer_after_sales_evidence_with_token(p_request_no text,p_token text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no));
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_request_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'case_no',c.case_no,'file_name',e.original_file_name,'mime_type',e.mime_type,'file_size',e.file_size,'review_status',e.review_status,'uploaded_at',e.uploaded_at) order by e.uploaded_at desc)
    from public.after_sales_evidence e join public.after_sales_cases c on c.id=e.case_id where e.request_no=v_request_no),'[]'::jsonb);
end;$$;
revoke all on function public.get_customer_after_sales_evidence_with_token(text,text) from public;
grant execute on function public.get_customer_after_sales_evidence_with_token(text,text) to anon,authenticated,service_role;
