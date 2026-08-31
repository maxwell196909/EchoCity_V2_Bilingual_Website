-- EchoCity: public recommendation RPC may aggregate private behavioral tables,
-- but callers must never receive direct access to those raw tables.
-- Keep the RPC output limited to already-public published video fields.

alter function public.get_recommended_videos_v1(integer, text) security definer;

revoke all on function public.get_recommended_videos_v1(integer, text) from public;
grant execute on function public.get_recommended_videos_v1(integer, text) to anon, authenticated, service_role;
