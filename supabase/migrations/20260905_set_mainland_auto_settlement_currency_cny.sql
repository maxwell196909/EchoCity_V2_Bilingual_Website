create or replace function public.create_order_settlement_after_acceptance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status = 'completed'
     and new.final_acceptance_status = 'accepted'
     and (old.status is distinct from new.status
          or old.final_acceptance_status is distinct from new.final_acceptance_status) then
    insert into public.order_settlements (
      request_no, customer_phone, worker_phone,
      total_amount, worker_amount, platform_fee, currency
    )
    values (
      new.request_no,
      coalesce(new.customer_phone, ''),
      new.assigned_worker_phone,
      greatest(coalesce(new.quote_amount, 0), 0),
      greatest(coalesce(new.worker_pay, 0), 0),
      greatest(coalesce(new.quote_amount, 0) - coalesce(new.worker_pay, 0), 0),
      'CNY'
    )
    on conflict (request_no) do nothing;
  end if;
  return new;
end;
$function$;
