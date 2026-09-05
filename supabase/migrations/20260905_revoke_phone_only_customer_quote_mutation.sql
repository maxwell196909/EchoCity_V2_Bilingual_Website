revoke execute on function public.submit_customer_quote_decision(text,text,boolean) from anon;
revoke execute on function public.submit_customer_quote_decision(text,text,boolean) from authenticated;
grant execute on function public.submit_customer_quote_decision(text,text,boolean) to service_role;
