-- EchoCity: keep the legacy homepage RPC name for compatibility, but route all
-- customer submissions through the v2 request pipeline so attribution,
-- workflow initialization and downstream horizontal data links stay unified.

create or replace function public.submit_customer_service_request(
  p_service_type text,
  p_description text,
  p_service_date date,
  p_start_time time without time zone,
  p_workers integer,
  p_duration text,
  p_postal_code text,
  p_address text,
  p_customer_name text,
  p_customer_phone text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.submit_customer_service_request_v2(
    p_service_type,
    p_description,
    p_service_date,
    p_start_time,
    p_workers,
    p_duration,
    p_postal_code,
    p_address,
    p_customer_name,
    p_customer_phone,
    'web',
    null,
    null,
    jsonb_build_object('entry_point','homepage_legacy_v1_bridge')
  );
end;
$$;

revoke all on function public.submit_customer_service_request(text,text,date,time without time zone,integer,text,text,text,text,text) from public;
grant execute on function public.submit_customer_service_request(text,text,date,time without time zone,integer,text,text,text,text,text) to anon, authenticated, service_role;
