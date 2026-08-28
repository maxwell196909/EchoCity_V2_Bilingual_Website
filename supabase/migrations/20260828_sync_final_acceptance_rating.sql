begin;

create or replace function public.submit_customer_final_acceptance_with_token(
  p_request_no text,
  p_token text,
  p_final_result text,
  p_service_completed boolean,
  p_final_rating integer,
  p_final_comments text,
  p_outstanding_details text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_request_no text:=upper(trim(p_request_no));
  v_customer_phone text;
  v_worker_id uuid;
  v_result jsonb;
begin
  if not public.validate_task_access_token(v_request_no,'customer',p_token) then
    raise exception 'TASK_LINK_EXPIRED_OR_INVALID';
  end if;

  select r.customer_phone,coalesce(r.worker_id,w.id)
  into v_customer_phone,v_worker_id
  from public.service_requests r
  left join public.service_workers w
    on regexp_replace(coalesce(w.phone,''),'\D','','g')=regexp_replace(coalesce(r.assigned_worker_phone,''),'\D','','g')
  where r.request_no=v_request_no
  limit 1
  for update of r;
  if not found then raise exception 'CUSTOMER_ORDER_NOT_FOUND'; end if;

  v_result:=public.submit_customer_final_acceptance(
    v_request_no,v_customer_phone,p_final_result,p_service_completed,
    p_final_rating,p_final_comments,p_outstanding_details
  );

  if v_worker_id is not null then
    update public.task_ratings
    set rating=p_final_rating,
        quality_rating=p_final_rating,
        comment=trim(p_final_comments),
        tags=jsonb_build_array('final_acceptance',p_final_result)
    where request_no=v_request_no and rated_worker_id=v_worker_id;

    if not found then
      insert into public.task_ratings(
        request_no,rated_worker_id,rating,quality_rating,comment,tags
      ) values(
        v_request_no,v_worker_id,p_final_rating,p_final_rating,
        trim(p_final_comments),jsonb_build_array('final_acceptance',p_final_result)
      );
    end if;
  end if;

  return v_result;
end;
$function$;

revoke all on function public.submit_customer_final_acceptance_with_token(text,text,text,boolean,integer,text,text) from public,anon,authenticated;
grant execute on function public.submit_customer_final_acceptance_with_token(text,text,text,boolean,integer,text,text) to anon,authenticated;

insert into public.task_ratings(request_no,rated_worker_id,rating,quality_rating,comment,tags)
select r.request_no,
       coalesce(r.worker_id,w.id),
       (r.final_acceptance_data->>'final_rating')::numeric,
       (r.final_acceptance_data->>'final_rating')::numeric,
       r.final_acceptance_data->>'final_comments',
       jsonb_build_array('final_acceptance',r.final_acceptance_status,'backfilled')
from public.service_requests r
left join public.service_workers w
  on regexp_replace(coalesce(w.phone,''),'\D','','g')=regexp_replace(coalesce(r.assigned_worker_phone,''),'\D','','g')
where coalesce(r.worker_id,w.id) is not null
  and coalesce(r.final_acceptance_data->>'final_rating','') ~ '^[1-5]$'
  and not exists(
    select 1 from public.task_ratings tr
    where tr.request_no=r.request_no and tr.rated_worker_id=coalesce(r.worker_id,w.id)
  );

commit;
