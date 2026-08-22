-- Secure customer lookup for the no-login MVP.
-- A request is returned only when both the request number and phone match.

begin;

create or replace function public.lookup_customer_request(
  p_request_no text,
  p_customer_phone text
)
returns table (
  request_no text,
  service_type text,
  description text,
  service_date date,
  start_time time,
  workers integer,
  duration text,
  address text,
  status text,
  quote_amount numeric,
  assigned_worker text
)
language sql
security definer
stable
set search_path = ''
as $function$
  select request.request_no, request.service_type, request.description,
    request.service_date, request.start_time, request.workers,
    request.duration, request.address, request.status,
    request.quote_amount, request.assigned_worker
  from public.service_requests request
  where request.request_no = upper(trim(p_request_no))
    and regexp_replace(coalesce(request.customer_phone, ''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g')
    and length(regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g'))
        between 7 and 20
    and length(trim(coalesce(p_request_no, ''))) between 8 and 80
  limit 1;
$function$;

revoke all on function public.lookup_customer_request(text, text) from public;
grant execute on function public.lookup_customer_request(text, text)
  to anon, authenticated, service_role;

comment on function public.lookup_customer_request(text, text) is
  'Returns a limited customer view only when request number and phone both match.';

commit;
