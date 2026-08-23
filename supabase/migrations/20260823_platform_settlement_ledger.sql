begin;

create or replace function public.get_platform_settlement_ledger_with_token(p_token text)
returns jsonb language plpgsql security definer stable set search_path='' as $function$
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then raise exception 'INVALID_PLATFORM_LINK'; end if;
  if not exists(select 1 from private.platform_dashboard_tokens t where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and t.revoked_at is null and t.expires_at>now()) then raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'ledger_count',(select count(*) from public.order_settlements),
      'customer_collected',(select coalesce(sum(total_amount),0) from public.order_settlements where status in ('payment_confirmed','receipt_confirmed','archived')),
      'customer_outstanding',(select coalesce(sum(total_amount),0) from public.order_settlements where status='awaiting_payment'),
      'worker_pending',(select coalesce(sum(worker_amount),0) from public.order_settlements where status='payment_confirmed'),
      'worker_settled',(select coalesce(sum(worker_amount),0) from public.order_settlements where status in ('receipt_confirmed','archived')),
      'platform_realized',(select coalesce(sum(platform_fee),0) from public.order_settlements where status='archived'),
      'refunded',(select coalesce(sum(refunded_amount),0) from public.payment_transactions)
    ),
    'settlements',coalesce((select jsonb_agg(jsonb_build_object(
      'request_no',s.request_no,'service_type',r.service_type,'total_amount',s.total_amount,
      'worker_amount',s.worker_amount,'platform_fee',s.platform_fee,'currency',s.currency,'status',s.status,
      'customer_paid_at',s.customer_paid_at,'worker_received_at',s.worker_received_at,'archived_at',s.archived_at,
      'invoice_status',(select i.status from public.invoice_requests i where i.request_no=s.request_no order by i.updated_at desc limit 1),
      'refunded_amount',(select coalesce(sum(p.refunded_amount),0) from public.payment_transactions p where p.request_no=s.request_no)
    ) order by s.updated_at desc) from public.order_settlements s join public.service_requests r on r.request_no=s.request_no),'[]'::jsonb)
  );
end;$function$;

revoke all on function public.get_platform_settlement_ledger_with_token(text) from public,anon,authenticated;
grant execute on function public.get_platform_settlement_ledger_with_token(text) to anon,authenticated,service_role;

commit;
