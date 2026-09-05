revoke execute on function public.confirm_customer_payment(text) from authenticated;
revoke execute on function public.confirm_worker_receipt(text) from authenticated;

grant execute on function public.confirm_customer_payment(text) to service_role;
grant execute on function public.confirm_worker_receipt(text) to service_role;
