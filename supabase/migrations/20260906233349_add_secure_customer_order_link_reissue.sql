create or replace function public.issue_customer_order_link_with_token(
  p_platform_token text,
  p_request_no text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_no text := upper(trim(p_request_no));
  v_token text;
  v_status text;
  v_expires_at timestamptz := now() + interval '30 days';
begin
  if p_platform_token is null
     or length(p_platform_token) < 64
     or length(p_platform_token) > 128
     or not exists (
       select 1
       from private.platform_dashboard_tokens t
       where t.token_hash = encode(extensions.digest(p_platform_token, 'sha256'), 'hex')
         and t.revoked_at is null
         and t.expires_at > now()
     )
  then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;

  select r.status
  into v_status
  from public.service_requests r
  where r.request_no = v_no;

  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.task_access_tokens (
    request_no, role, token_hash, expires_at, revoked_at
  ) values (
    v_no, 'customer',
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    v_expires_at, null
  )
  on conflict (request_no, role) do update
  set token_hash = excluded.token_hash,
      expires_at = excluded.expires_at,
      revoked_at = null,
      created_at = now();

  insert into public.task_events (
    request_no, event_type, action, actor_role, from_status, to_status, note, evidence
  ) values (
    v_no, 'access', 'reissue_customer_order_link', 'platform',
    v_status, v_status, '平台重新生成客户安全订单专链',
    jsonb_build_object('expires_hours', 720, 'previous_customer_token_revoked', true)
  );

  return jsonb_build_object(
    'request_no', v_no,
    'status', v_status,
    'customer_token', v_token,
    'expires_at', v_expires_at
  );
end;
$function$;

revoke all on function public.issue_customer_order_link_with_token(text, text)
from public, anon, authenticated;

grant execute on function public.issue_customer_order_link_with_token(text, text)
to anon, authenticated, service_role;
