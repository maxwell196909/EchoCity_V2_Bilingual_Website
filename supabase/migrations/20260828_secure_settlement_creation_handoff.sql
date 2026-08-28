begin;

create or replace function public.prepare_order_settlement_with_token(
  p_request_no text,
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_no text:=upper(trim(p_request_no));
  v_request public.service_requests%rowtype;
  v_settlement public.order_settlements%rowtype;
begin
  if not exists(
    select 1 from private.platform_dashboard_tokens t
    where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
      and t.revoked_at is null and t.expires_at>now()
  ) then raise exception 'INVALID_PLATFORM_TOKEN'; end if;

  select * into v_request from public.service_requests r where r.request_no=v_no;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_request.status not in ('completed','conditionally_completed','awaiting_payment','payment_confirmed','receipt_confirmed','closed') then
    raise exception 'ORDER_NOT_READY_FOR_SETTLEMENT';
  end if;

  select * into v_settlement from public.order_settlements s
  where s.request_no=v_no order by s.updated_at desc limit 1;

  return jsonb_build_object(
    'request_no',v_request.request_no,
    'service_type',v_request.service_type,
    'quote_amount',v_request.quote_amount,
    'order_status',v_request.status,
    'settlement',case when v_settlement.id is null then null else jsonb_build_object(
      'total_amount',v_settlement.total_amount,'worker_amount',v_settlement.worker_amount,
      'platform_fee',v_settlement.platform_fee,'currency',v_settlement.currency,
      'status',v_settlement.status
    ) end
  );
end;
$function$;

create or replace function public.create_order_settlement_with_token(
  p_request_no text,
  p_token text,
  p_total_amount numeric,
  p_worker_amount numeric,
  p_platform_fee numeric,
  p_currency text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_no text:=upper(trim(p_request_no));
  v_request public.service_requests%rowtype;
  v_settlement public.order_settlements%rowtype;
  v_currency text:=upper(trim(coalesce(p_currency,'CNY')));
  v_next_id bigint;
begin
  if not exists(
    select 1 from private.platform_dashboard_tokens t
    where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
      and t.revoked_at is null and t.expires_at>now()
  ) then raise exception 'INVALID_PLATFORM_TOKEN'; end if;
  if p_total_amount is null or p_total_amount<0 or p_worker_amount is null or p_worker_amount<0
     or p_platform_fee is null or p_platform_fee<0 then raise exception 'INVALID_SETTLEMENT_AMOUNT'; end if;
  if round(p_worker_amount+p_platform_fee,2)<>round(p_total_amount,2) then raise exception 'SETTLEMENT_SPLIT_MISMATCH'; end if;
  if v_currency not in ('CNY','USD') then raise exception 'INVALID_CURRENCY'; end if;

  select * into v_request from public.service_requests r where r.request_no=v_no for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_request.status not in ('completed','conditionally_completed','awaiting_payment') then
    raise exception 'ORDER_NOT_READY_FOR_SETTLEMENT';
  end if;
  if exists(select 1 from public.order_settlements s where s.request_no=v_no) then
    raise exception 'SETTLEMENT_ALREADY_EXISTS';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('echocity_order_settlements_id'));
  select coalesce(max(s.id),0)+1 into v_next_id from public.order_settlements s;
  insert into public.order_settlements(id,request_no,total_amount,worker_amount,platform_fee,currency,status,updated_at)
  values(v_next_id,v_no,round(p_total_amount,2),round(p_worker_amount,2),round(p_platform_fee,2),v_currency,'awaiting_payment',now())
  returning * into v_settlement;

  update public.service_requests set status='awaiting_payment',current_actor='platform',next_action='confirm_payment',updated_at=now()
  where request_no=v_no;
  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,evidence)
  values(v_no,'settlement','create_settlement','platform',v_request.status,'awaiting_payment',
    jsonb_build_object('total_amount',v_settlement.total_amount,'worker_amount',v_settlement.worker_amount,
      'platform_fee',v_settlement.platform_fee,'currency',v_settlement.currency));

  return jsonb_build_object('request_no',v_no,'status','awaiting_payment','next_action','confirm_payment');
end;
$function$;

revoke all on function public.prepare_order_settlement_with_token(text,text) from public;
revoke all on function public.create_order_settlement_with_token(text,text,numeric,numeric,numeric,text) from public;
grant execute on function public.prepare_order_settlement_with_token(text,text) to anon,authenticated,service_role;
grant execute on function public.create_order_settlement_with_token(text,text,numeric,numeric,numeric,text) to anon,authenticated,service_role;

commit;
