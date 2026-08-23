begin;

create table if not exists public.platform_incidents (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('order_sla','order_status','settlement','dispute','integration')),
  source_key text not null,
  request_no text,
  incident_type text not null,
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  title text not null,
  detail text,
  status text not null default 'open' check (status in ('open','in_review','resolved','dismissed')),
  owner_note text,
  first_detected_at timestamptz not null default now(),
  last_detected_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_type,source_key)
);

alter table public.platform_incidents enable row level security;
revoke all on table public.platform_incidents from anon,authenticated;

create or replace function public.sync_platform_incidents_internal()
returns void language plpgsql security definer set search_path='' as $function$
begin
  insert into public.platform_incidents(source_type,source_key,request_no,incident_type,severity,title,detail,last_detected_at)
  select 'order_sla',r.request_no,r.request_no,'sla_overdue',
    case when now()-r.updated_at>interval '72 hours' then 'high' else 'medium' end,
    '订单处理超时',format('状态 %s 已连续 %s 小时未更新',r.status,floor(extract(epoch from(now()-r.updated_at))/3600)),now()
  from public.service_requests r
  where ((r.status in ('submitted','reviewed','quoted','confirmed','quote_confirmed') and r.updated_at<now()-interval '24 hours')
    or (r.status in ('assigned','accepted','arrived','working','in_progress') and r.updated_at<now()-interval '48 hours'))
  on conflict(source_type,source_key) do update set detail=excluded.detail,severity=excluded.severity,last_detected_at=now(),updated_at=now();

  insert into public.platform_incidents(source_type,source_key,request_no,incident_type,severity,title,detail,last_detected_at)
  select 'order_status',r.request_no,r.request_no,
    case when r.status='disputed' then 'dispute' else 'rework' end,
    case when r.status='disputed' then 'high' else 'medium' end,
    case when r.status='disputed' then '订单进入争议' else '订单需要返工' end,
    coalesce(r.outstanding_issues,r.latest_issues_found,'请核对订单证据和处理责任'),now()
  from public.service_requests r where r.status in ('disputed','rework')
  on conflict(source_type,source_key) do update set detail=excluded.detail,severity=excluded.severity,last_detected_at=now(),updated_at=now();

  insert into public.platform_incidents(source_type,source_key,request_no,incident_type,severity,title,detail,last_detected_at)
  select 'settlement',s.request_no,s.request_no,'zero_amount_settlement','medium','0 元结算待核查','订单已生成结算记录，但结算总额为 0，禁止自动确认付款。',now()
  from public.order_settlements s where s.total_amount=0 and s.status='awaiting_payment'
  on conflict(source_type,source_key) do update set last_detected_at=now(),updated_at=now();

  insert into public.platform_incidents(source_type,source_key,request_no,incident_type,severity,title,detail,last_detected_at)
  select 'dispute',d.dispute_no,d.request_no,'formal_dispute',
    case when d.severity in ('critical','high') then d.severity else 'high' end,
    d.title,coalesce(d.description,'正式争议案件待平台处理'),now()
  from public.dispute_cases d where d.status not in ('resolved','closed','dismissed')
  on conflict(source_type,source_key) do update set detail=excluded.detail,severity=excluded.severity,last_detected_at=now(),updated_at=now();
end;$function$;

create or replace function public.get_platform_incident_center_with_token(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $function$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  perform public.sync_platform_incidents_internal();
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'open',(select count(*) from public.platform_incidents where status='open'),
      'in_review',(select count(*) from public.platform_incidents where status='in_review'),
      'high_priority',(select count(*) from public.platform_incidents where status in ('open','in_review') and severity in ('high','critical')),
      'resolved',(select count(*) from public.platform_incidents where status='resolved')
    ),
    'incidents',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'request_no',i.request_no,'incident_type',i.incident_type,'severity',i.severity,
      'title',i.title,'detail',i.detail,'status',i.status,'owner_note',i.owner_note,
      'first_detected_at',i.first_detected_at,'last_detected_at',i.last_detected_at,'acknowledged_at',i.acknowledged_at,'resolved_at',i.resolved_at
    ) order by case i.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,i.last_detected_at desc)
    from public.platform_incidents i),'[]'::jsonb)
  );
end;$function$;

create or replace function public.update_platform_incident_with_token(p_token text,p_incident_id uuid,p_action text,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_i public.platform_incidents%rowtype; v_status text;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  select * into v_i from public.platform_incidents where id=p_incident_id for update;
  if not found then raise exception 'INCIDENT_NOT_FOUND'; end if;
  if p_action='acknowledge' and v_i.status='open' then v_status:='in_review';
  elsif p_action='resolve' and v_i.status in ('open','in_review') and length(trim(coalesce(p_note,'')))>=3 then v_status:='resolved';
  elsif p_action='dismiss' and v_i.status in ('open','in_review') and length(trim(coalesce(p_note,'')))>=3 then v_status:='dismissed';
  else raise exception 'INVALID_INCIDENT_ACTION_OR_NOTE'; end if;
  update public.platform_incidents set status=v_status,owner_note=coalesce(nullif(trim(p_note),''),owner_note),acknowledged_at=case when p_action='acknowledge' then now() else acknowledged_at end,resolved_at=case when p_action in ('resolve','dismiss') then now() else null end,updated_at=now() where id=p_incident_id;
  if v_i.request_no is not null then
    insert into public.task_events(request_no,event_type,action,actor_role,note,evidence)
    values(v_i.request_no,'incident_management',p_action,'platform',p_note,jsonb_build_object('incident_id',p_incident_id,'incident_type',v_i.incident_type));
  end if;
  return jsonb_build_object('ok',true,'incident_id',p_incident_id,'status',v_status);
end;$function$;

revoke all on function public.sync_platform_incidents_internal() from public,anon,authenticated;
revoke all on function public.get_platform_incident_center_with_token(text) from public,anon,authenticated;
revoke all on function public.update_platform_incident_with_token(text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.get_platform_incident_center_with_token(text) to anon,authenticated,service_role;
grant execute on function public.update_platform_incident_with_token(text,uuid,text,text) to anon,authenticated,service_role;

commit;
