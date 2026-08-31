-- Align newer platform analytics modules with EchoCity's existing platform-token access model.
-- These RPCs remain protected by the hashed, expiring platform dashboard token.

do $$
declare
  fn_oid oid;
  fn_def text;
begin
  select p.oid into fn_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_platform_content_business_dashboard_v1'
  order by p.oid desc limit 1;
  if fn_oid is null then raise exception 'FUNCTION_NOT_FOUND: get_platform_content_business_dashboard_v1'; end if;
  fn_def := pg_get_functiondef(fn_oid);
  fn_def := replace(fn_def, E'  if auth.uid() is null then\n    raise exception ''AUTH_REQUIRED'';\n  end if;\n', '');
  execute fn_def;

  select p.oid into fn_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_platform_demand_supply_v1'
  order by p.oid desc limit 1;
  if fn_oid is null then raise exception 'FUNCTION_NOT_FOUND: get_platform_demand_supply_v1'; end if;
  fn_def := pg_get_functiondef(fn_oid);
  fn_def := replace(fn_def, E'  if auth.uid() is null then\n    raise exception ''AUTH_REQUIRED'';\n  end if;\n', '');
  execute fn_def;
end $$;

grant execute on function public.get_platform_content_business_dashboard_v1(text,integer,integer) to anon, authenticated;
grant execute on function public.get_platform_demand_supply_v1(text,integer,integer) to anon, authenticated;
