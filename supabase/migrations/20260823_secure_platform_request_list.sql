-- Secure bearer-link access for the no-login platform dashboard MVP.

begin;

create table if not exists private.platform_dashboard_tokens (
  id uuid primary key default extensions.gen_random_uuid(),
  token_hash text not null unique,
  label text not null default 'platform dashboard',
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

revoke all on table private.platform_dashboard_tokens
  from public, anon, authenticated;

create or replace function public.list_platform_requests_with_token(
  p_token text
)
returns table (
  request_no text,
  customer_phone text,
  description text,
  service_type text,
  status text,
  updated_at timestamptz
)
language plpgsql
security definer
stable
set search_path = ''
as $function$
begin
  if p_token is null or length(p_token) < 64 or length(p_token) > 128 then
    raise exception 'INVALID_PLATFORM_LINK';
  end if;

  if not exists (
    select 1
    from private.platform_dashboard_tokens access_token
    where access_token.token_hash =
      encode(extensions.digest(p_token, 'sha256'), 'hex')
      and access_token.revoked_at is null
      and access_token.expires_at > now()
  ) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;

  return query
  select
    request.request_no,
    request.customer_phone,
    request.description,
    request.service_type,
    request.status,
    request.updated_at
  from public.service_requests request
  order by request.updated_at desc
  limit 100;
end;
$function$;

revoke all on function public.list_platform_requests_with_token(text)
  from public, anon, authenticated;
grant execute on function public.list_platform_requests_with_token(text)
  to anon, authenticated, service_role;

comment on function public.list_platform_requests_with_token(text) is
  'Lists the latest platform requests only for a valid revocable dashboard bearer token.';

commit;
