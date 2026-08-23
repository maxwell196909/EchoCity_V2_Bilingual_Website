alter table public.after_sales_cases drop constraint if exists after_sales_cases_status_check;
alter table public.after_sales_cases add constraint after_sales_cases_status_check check(status in ('open','in_review','repairing','awaiting_reinspection','disputed','closed','rejected'));
alter table public.after_sales_cases add column if not exists customer_reinspection_result text check(customer_reinspection_result in ('approved','rework','conditional','disputed'));
alter table public.after_sales_cases add column if not exists customer_reinspection_note text;
alter table public.after_sales_cases add column if not exists customer_reinspection_confirmed_at timestamptz;
alter table public.after_sales_cases add column if not exists reinspection_round integer not null default 0;

create or replace function public.submit_customer_after_sales_reinspection_with_token(p_request_no text,p_token text,p_case_no text,p_result text,p_note text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); c public.after_sales_cases; v_status text;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_request_no,'customer',p_token) then raise exception 'CUSTOMER_LINK_EXPIRED_OR_INVALID'; end if;
  if p_result not in ('approved','rework','conditional','disputed') or nullif(trim(p_note),'') is null then raise exception 'RESULT_AND_NOTE_REQUIRED'; end if;
  select * into c from public.after_sales_cases where request_no=v_request_no and case_no=p_case_no for update;
  if c.id is null then raise exception 'AFTER_SALES_CASE_NOT_FOUND'; end if;
  if c.status<>'awaiting_reinspection' then raise exception 'CASE_NOT_AWAITING_CUSTOMER_REINSPECTION'; end if;
  v_status:=case p_result when 'approved' then 'awaiting_reinspection' when 'rework' then 'repairing' when 'conditional' then 'in_review' else 'disputed' end;
  update public.after_sales_cases set status=v_status,customer_reinspection_result=p_result,customer_reinspection_note=trim(p_note),customer_reinspection_confirmed_at=now(),reinspection_round=reinspection_round+1,updated_at=now() where id=c.id returning * into c;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,from_status,to_status,note,evidence)
  values(c.id,c.request_no,'customer','reinspection_decision','awaiting_reinspection',v_status,trim(p_note),jsonb_build_object('result',p_result,'round',c.reinspection_round));
  return jsonb_build_object('ok',true,'case_no',c.case_no,'result',p_result,'status',c.status,'round',c.reinspection_round);
end;$$;

create or replace function public.update_after_sales_case_with_token(p_token text,p_case_id uuid,p_action text,p_note text,p_reinspection_result text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare c public.after_sales_cases; new_status text;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if nullif(trim(p_note),'') is null then raise exception 'HUMAN_NOTE_REQUIRED'; end if;
  select * into c from public.after_sales_cases where id=p_case_id for update;
  if c.id is null then raise exception 'CASE_NOT_FOUND'; end if;
  if p_action='review' and c.status not in ('open','disputed') then raise exception 'INVALID_CASE_TRANSITION'; end if;
  if p_action='repair' and c.status not in ('in_review','repairing') then raise exception 'INVALID_CASE_TRANSITION'; end if;
  if p_action='reinspect' and c.status<>'repairing' then raise exception 'INVALID_CASE_TRANSITION'; end if;
  if p_action='close' and (c.status<>'awaiting_reinspection' or c.customer_reinspection_result is distinct from 'approved' or c.customer_reinspection_confirmed_at is null) then raise exception 'CUSTOMER_REINSPECTION_APPROVAL_REQUIRED'; end if;
  if p_action='reject' and c.status not in ('open','in_review','disputed') then raise exception 'INVALID_CASE_TRANSITION'; end if;
  new_status:=case p_action when 'review' then 'in_review' when 'repair' then 'repairing' when 'reinspect' then 'awaiting_reinspection' when 'close' then 'closed' when 'reject' then 'rejected' else null end;
  if new_status is null then raise exception 'INVALID_ACTION'; end if;
  update public.after_sales_cases set status=new_status,platform_note=trim(p_note),reinspection_result=case when p_action='close' then coalesce(nullif(trim(p_reinspection_result),''),'客户复验通过，平台归档') else reinspection_result end,customer_reinspection_result=case when p_action='reinspect' then null else customer_reinspection_result end,customer_reinspection_note=case when p_action='reinspect' then null else customer_reinspection_note end,customer_reinspection_confirmed_at=case when p_action='reinspect' then null else customer_reinspection_confirmed_at end,closed_at=case when new_status in ('closed','rejected') then now() else null end,updated_at=now() where id=p_case_id returning * into c;
  return jsonb_build_object('ok',true,'case_no',c.case_no,'status',c.status);
end;$$;

revoke all on function public.submit_customer_after_sales_reinspection_with_token(text,text,text,text,text) from public;
grant execute on function public.submit_customer_after_sales_reinspection_with_token(text,text,text,text,text) to anon,authenticated,service_role;
