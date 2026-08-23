begin;

create table if not exists public.worker_qualification_reviews (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.service_workers(id) on delete cascade,
  decision text not null check (decision in ('approved','rejected')),
  identity_checked boolean not null default false,
  phone_checked boolean not null default false,
  safety_briefed boolean not null default false,
  skills text[] not null default '{}',
  review_note text not null,
  reviewer_role text not null default 'platform',
  created_at timestamptz not null default now()
);

alter table public.worker_qualification_reviews enable row level security;
revoke all on table public.worker_qualification_reviews from anon,authenticated;

create or replace function public.review_platform_worker_qualification_with_token(
  p_token text,p_worker_id uuid,p_decision text,p_identity_checked boolean,p_phone_checked boolean,
  p_safety_briefed boolean,p_skills text[],p_note text
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_worker public.service_workers%rowtype;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select * into v_worker from public.service_workers where id=p_worker_id for update;
  if not found then raise exception 'WORKER_NOT_FOUND'; end if;
  if p_decision not in ('approved','rejected') or length(trim(coalesce(p_note,'')))<3 then raise exception 'INVALID_REVIEW_DECISION_OR_NOTE'; end if;
  if p_decision='approved' and (not coalesce(p_identity_checked,false) or not coalesce(p_phone_checked,false) or not coalesce(p_safety_briefed,false) or coalesce(cardinality(p_skills),0)<1) then raise exception 'APPROVAL_CHECKLIST_INCOMPLETE'; end if;
  insert into public.worker_qualification_reviews(worker_id,decision,identity_checked,phone_checked,safety_briefed,skills,review_note)
  values(p_worker_id,p_decision,coalesce(p_identity_checked,false),coalesce(p_phone_checked,false),coalesce(p_safety_briefed,false),coalesce(p_skills,'{}'),trim(p_note));
  update public.service_workers set
    verification_status=case when p_decision='approved' then 'verified' else 'rejected' end,
    status=case when p_decision='approved' then 'active' else 'paused' end,
    availability_status=case when p_decision='approved' then 'available' else 'offline' end,
    skills=case when p_decision='approved' then p_skills else skills end,updated_at=now()
  where id=p_worker_id;
  insert into public.worker_credit_events(worker_id,event_type,score_delta,reason,evidence)
  values(p_worker_id,'qualification_review',0,case when p_decision='approved' then '平台审核准入通过' else '平台审核准入未通过' end,jsonb_build_object('decision',p_decision,'note',trim(p_note),'skills',coalesce(p_skills,'{}')));
  return jsonb_build_object('ok',true,'worker_id',p_worker_id,'decision',p_decision,'verification_status',case when p_decision='approved' then 'verified' else 'rejected' end);
end;$function$;

create or replace function public.set_platform_worker_availability_with_token(p_token text,p_worker_id uuid,p_availability text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_worker public.service_workers%rowtype;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  if p_availability not in ('available','offline') or length(trim(coalesce(p_note,'')))<2 then raise exception 'INVALID_AVAILABILITY_OR_NOTE'; end if;
  select * into v_worker from public.service_workers where id=p_worker_id for update;
  if not found then raise exception 'WORKER_NOT_FOUND'; end if;
  if v_worker.status<>'active' or v_worker.verification_status<>'verified' then raise exception 'WORKER_NOT_QUALIFIED'; end if;
  update public.service_workers set availability_status=p_availability,last_active_at=case when p_availability='available' then now() else last_active_at end,updated_at=now() where id=p_worker_id;
  insert into public.worker_credit_events(worker_id,event_type,score_delta,reason,evidence)
  values(p_worker_id,'availability_changed',0,'平台记录服务人员接单状态',jsonb_build_object('from',v_worker.availability_status,'to',p_availability,'note',trim(p_note)));
  return jsonb_build_object('ok',true,'worker_id',p_worker_id,'availability_status',p_availability);
end;$function$;

revoke all on function public.review_platform_worker_qualification_with_token(text,uuid,text,boolean,boolean,boolean,text[],text) from public,anon,authenticated;
revoke all on function public.set_platform_worker_availability_with_token(text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.review_platform_worker_qualification_with_token(text,uuid,text,boolean,boolean,boolean,text[],text) to anon,authenticated,service_role;
grant execute on function public.set_platform_worker_availability_with_token(text,uuid,text,text) to anon,authenticated,service_role;

commit;
