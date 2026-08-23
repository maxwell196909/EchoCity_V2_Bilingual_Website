begin;

create or replace function public.get_order_settlement_with_token(
  p_request_no text,p_role text,p_token text
) returns jsonb language plpgsql security definer stable set search_path='' as $function$
declare v_settlement public.order_settlements%rowtype;
begin
  if p_role='platform' then
    if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'INVALID_PLATFORM_TOKEN'; end if;
  elsif p_role='worker' then
    if not exists(select 1 from public.task_access_tokens t where t.request_no=upper(trim(p_request_no)) and t.role='worker' and t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'INVALID_WORKER_TOKEN'; end if;
  else raise exception 'INVALID_SETTLEMENT_ROLE';
  end if;
  select * into v_settlement from public.order_settlements s where s.request_no=upper(trim(p_request_no));
  if not found then raise exception 'SETTLEMENT_NOT_FOUND'; end if;
  return jsonb_build_object('request_no',v_settlement.request_no,'total_amount',v_settlement.total_amount,'worker_amount',v_settlement.worker_amount,'platform_fee',v_settlement.platform_fee,'currency',v_settlement.currency,'status',v_settlement.status,'customer_paid_at',v_settlement.customer_paid_at,'worker_received_at',v_settlement.worker_received_at,'archived_at',v_settlement.archived_at);
end;$function$;

create or replace function public.advance_order_settlement_with_token(
  p_request_no text,p_role text,p_token text,p_action text
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_settlement public.order_settlements%rowtype; v_status text; v_next text; v_actor text;
begin
  if p_role='platform' then
    if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'INVALID_PLATFORM_TOKEN'; end if;
  elsif p_role='worker' then
    if not exists(select 1 from public.task_access_tokens t where t.request_no=upper(trim(p_request_no)) and t.role='worker' and t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'INVALID_WORKER_TOKEN'; end if;
  else raise exception 'INVALID_SETTLEMENT_ROLE';
  end if;
  select * into v_settlement from public.order_settlements s where s.request_no=upper(trim(p_request_no)) for update;
  if not found then raise exception 'SETTLEMENT_NOT_FOUND'; end if;

  if p_action='confirm_payment' and p_role='platform' and v_settlement.status='awaiting_payment' then
    update public.order_settlements set status='payment_confirmed',customer_paid_at=now(),updated_at=now() where id=v_settlement.id;
    v_status:='payment_confirmed';v_actor:='worker';v_next:='confirm_worker_receipt';
  elsif p_action='confirm_receipt' and p_role='worker' and v_settlement.status='payment_confirmed' then
    update public.order_settlements set status='receipt_confirmed',worker_received_at=now(),updated_at=now() where id=v_settlement.id;
    v_status:='receipt_confirmed';v_actor:='platform';v_next:='archive_order';
  elsif p_action='archive' and p_role='platform' and v_settlement.status='receipt_confirmed' then
    update public.order_settlements set status='archived',archived_at=now(),updated_at=now() where id=v_settlement.id;
    v_status:='archived';v_actor:='platform';v_next:='none';
  else raise exception 'INVALID_SETTLEMENT_TRANSITION';
  end if;

  update public.service_requests set status=case when v_status='archived' then 'closed' else status end,current_actor=v_actor,next_action=v_next,updated_at=now() where request_no=v_settlement.request_no;
  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,evidence)
  values(v_settlement.request_no,'settlement',p_action,p_role,v_settlement.status,v_status,jsonb_build_object('settlement_id',v_settlement.id));
  return jsonb_build_object('request_no',v_settlement.request_no,'status',v_status,'next_action',v_next);
end;$function$;

revoke all on function public.get_order_settlement_with_token(text,text,text) from public,anon,authenticated;
revoke all on function public.advance_order_settlement_with_token(text,text,text,text) from public,anon,authenticated;
grant execute on function public.get_order_settlement_with_token(text,text,text) to anon,authenticated,service_role;
grant execute on function public.advance_order_settlement_with_token(text,text,text,text) to anon,authenticated,service_role;

commit;
