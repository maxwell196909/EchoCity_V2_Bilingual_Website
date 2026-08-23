create or replace function public.issue_after_sales_worker_link_with_token(p_platform_token text,p_case_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare c public.after_sales_cases; r public.service_requests; v_token text;
begin
  if p_platform_token is null or length(p_platform_token)<64 or length(p_platform_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select * into c from public.after_sales_cases where id=p_case_id;
  if c.id is null or c.status<>'in_review' then raise exception 'CASE_NOT_READY_FOR_WORKER'; end if;
  select * into r from public.service_requests where request_no=c.request_no;
  if nullif(regexp_replace(coalesce(c.responsible_worker_phone,''),'\D','','g'),'') is null or regexp_replace(coalesce(c.responsible_worker_phone,''),'\D','','g')<>regexp_replace(coalesce(r.assigned_worker_phone,''),'\D','','g') then raise exception 'RESPONSIBLE_WORKER_NOT_CONFIRMED'; end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.task_access_tokens(request_no,role,token_hash,expires_at,revoked_at) values(c.request_no,'worker',encode(extensions.digest(v_token,'sha256'),'hex'),now()+interval '30 days',null)
  on conflict(request_no,role) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,revoked_at=null;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,from_status,to_status,note,evidence) values(c.id,c.request_no,'platform','worker_link_issued',c.status,c.status,'平台签发售后整改专属链接',jsonb_build_object('expires_in_days',30));
  return jsonb_build_object('request_no',c.request_no,'case_no',c.case_no,'worker_token',v_token,'expires_at',now()+interval '30 days');
end;$$;

create or replace function public.get_worker_after_sales_with_token(p_request_no text,p_token text,p_case_no text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); c public.after_sales_cases; w public.warranty_records; r public.service_requests;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_request_no,'worker',p_token) then raise exception 'WORKER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into c from public.after_sales_cases where request_no=v_request_no and case_no=p_case_no;
  select * into r from public.service_requests where request_no=v_request_no;
  if c.id is null or regexp_replace(coalesce(c.responsible_worker_phone,''),'\D','','g')<>regexp_replace(coalesce(r.assigned_worker_phone,''),'\D','','g') then raise exception 'REMEDIATION_NOT_ASSIGNED_TO_WORKER'; end if;
  select * into w from public.warranty_records where request_no=v_request_no;
  return jsonb_build_object('case',jsonb_build_object('case_no',c.case_no,'request_no',c.request_no,'status',c.status,'issue',c.issue_description,'platform_note',c.platform_note,'scope',w.coverage_scope,'exclusions',w.exclusions,'response_hours',w.response_hours),
    'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'file_name',e.original_file_name,'mime_type',e.mime_type,'file_size',e.file_size,'uploaded_by_role',e.uploaded_by_role,'review_status',e.review_status,'uploaded_at',e.uploaded_at) order by e.uploaded_at) from public.after_sales_evidence e where e.case_id=c.id and (e.uploaded_by_role='worker' or e.review_status='accepted')),'[]'::jsonb));
end;$$;

create or replace function public.transition_worker_after_sales_with_token(p_request_no text,p_token text,p_case_no text,p_action text,p_note text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); c public.after_sales_cases; r public.service_requests; v_status text;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_request_no,'worker',p_token) then raise exception 'WORKER_LINK_EXPIRED_OR_INVALID'; end if;
  if nullif(trim(p_note),'') is null then raise exception 'WORKER_NOTE_REQUIRED'; end if;
  select * into c from public.after_sales_cases where request_no=v_request_no and case_no=p_case_no for update;
  select * into r from public.service_requests where request_no=v_request_no;
  if c.id is null or regexp_replace(coalesce(c.responsible_worker_phone,''),'\D','','g')<>regexp_replace(coalesce(r.assigned_worker_phone,''),'\D','','g') then raise exception 'REMEDIATION_NOT_ASSIGNED_TO_WORKER'; end if;
  if p_action='accept' and c.status='in_review' then v_status:='repairing';
  elsif p_action='submit_reinspection' and c.status='repairing' then
    if not exists(select 1 from public.after_sales_evidence e where e.case_id=c.id and e.uploaded_by_role='worker') then raise exception 'WORKER_REMEDIATION_EVIDENCE_REQUIRED'; end if;
    v_status:='awaiting_reinspection';
  else raise exception 'INVALID_WORKER_TRANSITION'; end if;
  update public.after_sales_cases set status=v_status,platform_note=case when p_action='submit_reinspection' then trim(p_note) else platform_note end,customer_reinspection_result=null,customer_reinspection_note=null,customer_reinspection_confirmed_at=null,updated_at=now() where id=c.id returning * into c;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,from_status,to_status,note,evidence) values(c.id,c.request_no,'worker',p_action,case when p_action='accept' then 'in_review' else 'repairing' end,v_status,trim(p_note),'{}');
  return jsonb_build_object('ok',true,'case_no',c.case_no,'status',c.status);
end;$$;

create or replace function public.commit_worker_after_sales_evidence_with_token(p_request_no text,p_token text,p_case_no text,p_storage_path text,p_file_name text,p_file_size bigint,p_mime_type text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request_no text:=upper(trim(p_request_no)); c public.after_sales_cases; obj storage.objects; e public.after_sales_evidence;
begin
  if p_token is null or length(p_token)<>64 or not public.validate_task_access_token(v_request_no,'worker',p_token) then raise exception 'WORKER_LINK_EXPIRED_OR_INVALID'; end if;
  select * into c from public.after_sales_cases where request_no=v_request_no and case_no=p_case_no;
  if c.id is null or c.status<>'repairing' then raise exception 'CASE_NOT_IN_REMEDIATION'; end if;
  if p_storage_path not like v_request_no||'/worker/after-sales/'||p_case_no||'/%' then raise exception 'INVALID_EVIDENCE_PATH'; end if;
  if p_mime_type in ('image/jpeg','image/png','image/heic') and p_file_size between 1 and 15728640 then null; elsif p_mime_type in ('video/mp4','video/quicktime') and p_file_size between 1 and 104857600 then null; else raise exception 'INVALID_EVIDENCE_FILE'; end if;
  select * into obj from storage.objects where bucket_id='work-evidence' and name=p_storage_path;if obj.id is null then raise exception 'UPLOADED_OBJECT_NOT_FOUND'; end if;
  insert into public.after_sales_evidence(case_id,request_no,storage_path,original_file_name,mime_type,file_size,uploaded_by_role,object_version) values(c.id,v_request_no,p_storage_path,left(p_file_name,180),p_mime_type,p_file_size,'worker',obj.version::text) returning * into e;
  insert into public.after_sales_events(case_id,request_no,actor_role,action,from_status,to_status,note,evidence) values(c.id,c.request_no,'worker','remediation_evidence_uploaded',c.status,c.status,'服务人员上传整改证据',jsonb_build_object('evidence_id',e.id));
  return jsonb_build_object('ok',true,'evidence_id',e.id);
end;$$;

revoke all on function public.issue_after_sales_worker_link_with_token(text,uuid),public.get_worker_after_sales_with_token(text,text,text),public.transition_worker_after_sales_with_token(text,text,text,text,text),public.commit_worker_after_sales_evidence_with_token(text,text,text,text,text,bigint,text) from public;
grant execute on function public.issue_after_sales_worker_link_with_token(text,uuid),public.get_worker_after_sales_with_token(text,text,text),public.transition_worker_after_sales_with_token(text,text,text,text,text),public.commit_worker_after_sales_evidence_with_token(text,text,text,text,text,bigint,text) to anon,authenticated,service_role;
