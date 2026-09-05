-- Extend the customer secure order token so one link can cover quote,
-- progress and later customer actions through a typical service lifecycle.

create or replace function public.issue_customer_quote_link_with_token(
  p_platform_token text,
  p_request_no text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_no text:=upper(trim(p_request_no));
  v_token text;
begin
  if p_platform_token is null
     or length(p_platform_token)<64
     or length(p_platform_token)>128 then
    raise exception 'INVALID_PLATFORM_LINK';
  end if;

  if not exists(
    select 1
    from private.platform_dashboard_tokens t
    where t.token_hash=encode(extensions.digest(p_platform_token,'sha256'),'hex')
      and t.revoked_at is null
      and t.expires_at>now()
  ) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;

  if not exists(
    select 1
    from public.service_requests r
    where r.request_no=v_no
      and r.quote_amount is not null
      and r.status in ('quoted','quote_confirmed','quote_declined')
  ) then
    raise exception 'QUOTE_NOT_READY';
  end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');

  insert into public.task_access_tokens(request_no,role,token_hash,expires_at,revoked_at)
  values(
    v_no,
    'customer',
    encode(extensions.digest(v_token,'sha256'),'hex'),
    now()+interval '30 days',
    null
  )
  on conflict(request_no,role) do update
    set token_hash=excluded.token_hash,
        expires_at=excluded.expires_at,
        revoked_at=null;

  insert into public.task_events(
    request_no,event_type,action,actor_role,to_status,note,evidence
  ) values(
    v_no,'access','issue_customer_order_link','platform','quoted',
    '平台生成客户安全订单链接',jsonb_build_object('expires_hours',720)
  );

  return jsonb_build_object(
    'request_no',v_no,
    'customer_token',v_token,
    'expires_at',now()+interval '30 days'
  );
end;
$$;

revoke all on function public.issue_customer_quote_link_with_token(text,text) from public;
grant execute on function public.issue_customer_quote_link_with_token(text,text) to anon,authenticated,service_role;
