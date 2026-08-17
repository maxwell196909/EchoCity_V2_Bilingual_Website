-- EchoCity security baseline: trigger helper functions
-- Scope: harden two internal trigger functions without changing business RPCs.

begin;

-- Prevent object-shadowing through a caller-controlled search_path.
alter function public.set_updated_at()
  set search_path = '';

-- These functions are invoked internally by database triggers.
-- Browser clients and ordinary signed-in users must not call them directly.
revoke execute on function public.set_updated_at()
  from public, anon, authenticated;

revoke execute on function public.handle_new_user()
  from public, anon, authenticated;

-- Retain explicit backend access for trusted server operations.
grant execute on function public.set_updated_at()
  to service_role;

grant execute on function public.handle_new_user()
  to service_role;

comment on function public.set_updated_at() is
  'Internal trigger helper. Direct client execution is disabled.';

comment on function public.handle_new_user() is
  'Internal auth trigger helper. Direct client execution is disabled.';

commit;

-- Intentionally unchanged in this migration:
-- public.confirm_customer_payment(text)
-- public.confirm_worker_receipt(text)
-- public.transition_task(...)
-- These business RPCs already validate the signed-in user and task role.
