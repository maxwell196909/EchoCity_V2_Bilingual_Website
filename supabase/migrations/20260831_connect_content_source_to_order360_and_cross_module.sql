-- Carry video/live attribution into Order 360 and the platform cross-module matrix.

do $$
declare
  fn_oid oid;
  fn_def text;
begin
  select p.oid into fn_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_platform_order_360_with_token' order by p.oid desc limit 1;
  if fn_oid is null then raise exception 'FUNCTION_NOT_FOUND: get_platform_order_360_with_token'; end if;
  fn_def := pg_get_functiondef(fn_oid);
  if position($needle$'source',jsonb_build_object($needle$ in fn_def) = 0 then
    fn_def := replace(fn_def,
      $old$    'worker',(select jsonb_build_object$old$,
      $new$    'source',jsonb_build_object('content_type',r.source_content_type,'video_id',r.source_video_id,'live_room_id',r.source_live_room_id,'creator_id',r.source_creator_id,'metadata',r.source_metadata,'video_title',(select v.title from public.videos v where v.id=r.source_video_id),'live_title',(select l.title from public.live_rooms l where l.id=r.source_live_room_id),'creator_name',(select p.display_name from public.profiles p where p.id=r.source_creator_id)),
    'worker',(select jsonb_build_object$new$);
  end if;
  execute fn_def;

  select p.oid into fn_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_platform_cross_module_matrix_with_token' order by p.oid desc limit 1;
  if fn_oid is null then raise exception 'FUNCTION_NOT_FOUND: get_platform_cross_module_matrix_with_token'; end if;
  fn_def := pg_get_functiondef(fn_oid);
  if position('r.source_content_type' in fn_def) = 0 then
    fn_def := replace(fn_def,
      $old$select r.request_no,r.service_type,r.status as order_status,r.current_actor,r.next_action,r.updated_at,$old$,
      $new$select r.request_no,r.service_type,r.status as order_status,r.current_actor,r.next_action,r.updated_at,r.source_content_type,r.source_video_id,r.source_live_room_id,r.source_creator_id,$new$);
    fn_def := replace(fn_def,
      $old$'open_incidents',open_incidents,'health',health,'updated_at',updated_at)$old$,
      $new$'open_incidents',open_incidents,'health',health,'source_content_type',source_content_type,'source_video_id',source_video_id,'source_live_room_id',source_live_room_id,'source_creator_id',source_creator_id,'updated_at',updated_at)$new$);
  end if;
  execute fn_def;
end $$;
