create or replace function public.activate_warranty_with_token(p_token text, p_warranty_id uuid, p_warranty_days integer, p_scope text, p_exclusions text, p_response_hours integer, p_note text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  w public.warranty_records;
begin
  if p_token is null or length(p_token)<64 or length(p_token)>128 then
    raise exception 'INVALID_PLATFORM_LINK';
  end if;
  if not exists(
    select 1 from private.platform_dashboard_tokens t
    where t.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
      and t.revoked_at is null and t.expires_at>now()
  ) then
    raise exception 'PLATFORM_LINK_EXPIRED_OR_INVALID';
  end if;
  if p_warranty_days is null or p_warranty_days<1 or p_warranty_days>3650 then
    raise exception 'INVALID_WARRANTY_DAYS';
  end if;
  if nullif(trim(p_scope),'') is null
     or nullif(trim(p_exclusions),'') is null
     or p_response_hours is null or p_response_hours<1 or p_response_hours>720
     or nullif(trim(p_note),'') is null then
    raise exception 'TERMS_AND_APPROVAL_NOTE_REQUIRED';
  end if;

  update public.warranty_records
     set status='active',
         warranty_start_at=coalesce(warranty_start_at,now()),
         warranty_end_at=coalesce(warranty_start_at,now())+make_interval(days=>p_warranty_days),
         coverage_scope=trim(p_scope),
         exclusions=trim(p_exclusions),
         response_hours=p_response_hours,
         approval_note=trim(p_note),
         approved_at=now(),
         updated_at=now()
   where id=p_warranty_id
     and status='pending_terms'
  returning * into w;

  if w.id is null then
    if exists(select 1 from public.warranty_records where id=p_warranty_id) then
      raise exception 'WARRANTY_ALREADY_ACTIVATED_OR_NOT_PENDING';
    end if;
    raise exception 'WARRANTY_NOT_FOUND';
  end if;

  insert into public.task_events(request_no,event_type,action,actor_role,from_status,to_status,note,evidence)
  values(
    w.request_no,
    'warranty',
    'activate_warranty',
    'platform',
    'pending_terms',
    'active',
    trim(p_note),
    jsonb_build_object(
      'warranty_id',w.id,
      'warranty_days',p_warranty_days,
      'response_hours',p_response_hours,
      'scope',trim(p_scope),
      'exclusions',trim(p_exclusions),
      'end_at',w.warranty_end_at
    )
  );

  return jsonb_build_object(
    'ok',true,
    'request_no',w.request_no,
    'status',w.status,
    'end_at',w.warranty_end_at
  );
end;
$function$;
