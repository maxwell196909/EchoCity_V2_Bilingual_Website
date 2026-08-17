-- EchoCity three-party task data policies (compatibility stage)
-- Adds authenticated customer/worker/platform access without removing legacy
-- anonymous service-request policies. Legacy access will be removed only after
-- the dedicated-link frontend has been deployed and tested.

begin;

-- Public organizations may be discovered; private organizations are visible
-- only to their active members.
drop policy if exists "Public or members can read organizations"
  on public.organizations;
create policy "Public or members can read organizations"
on public.organizations
for select
to authenticated
using (
  coalesce(is_public, false)
  or exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = organizations.id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  )
);

-- Every active participant in the same task can see inspection status.
drop policy if exists "Participants can read task inspections"
  on public.task_inspections;
create policy "Participants can read task inspections"
on public.task_inspections
for select
to authenticated
using ((select public.is_task_participant(request_no)));

-- Workers with the inspection.submit permission may submit an inspection.
drop policy if exists "Authorized workers can submit inspections"
  on public.task_inspections;
create policy "Authorized workers can submit inspections"
on public.task_inspections
for insert
to authenticated
with check (
  submitted_by = (select auth.uid())
  and submitted_role = 'worker'
  and (select public.is_task_participant(request_no))
  and (select public.user_has_task_permission(
    request_no,
    'inspection.submit'
  ))
);

-- Platform reviewers may review an inspection for a managed task.
drop policy if exists "Platform can review task inspections"
  on public.task_inspections;
create policy "Platform can review task inspections"
on public.task_inspections
for update
to authenticated
using (
  (select public.is_task_participant(request_no))
  and (select public.user_has_task_permission(
    request_no,
    'inspection.approve'
  ))
)
with check (
  reviewer_id = (select auth.uid())
  and reviewer_role = 'platform'
  and (select public.is_task_participant(request_no))
  and (select public.user_has_task_permission(
    request_no,
    'inspection.approve'
  ))
);

-- Every active participant can see evidence attached to the same task.
drop policy if exists "Participants can read task evidence v2"
  on public.task_evidence;
create policy "Participants can read task evidence v2"
on public.task_evidence
for select
to authenticated
using ((select public.is_task_participant(request_no)));

-- Authorized workers may upload task evidence under their own identity.
drop policy if exists "Authorized workers can upload task evidence"
  on public.task_evidence;
create policy "Authorized workers can upload task evidence"
on public.task_evidence
for insert
to authenticated
with check (
  uploaded_by = (select auth.uid())
  and uploader_role = 'worker'
  and (select public.is_task_participant(request_no))
  and (select public.user_has_task_permission(
    request_no,
    'evidence.upload'
  ))
);

-- Uploaders may correct metadata until a human review has been recorded.
drop policy if exists "Uploaders can revise pending task evidence"
  on public.task_evidence;
create policy "Uploaders can revise pending task evidence"
on public.task_evidence
for update
to authenticated
using (
  uploaded_by = (select auth.uid())
  and human_reviewed_at is null
  and (select public.is_task_participant(request_no))
)
with check (
  uploaded_by = (select auth.uid())
  and human_reviewed_at is null
  and (select public.is_task_participant(request_no))
);

commit;

-- Deliberately unchanged in this compatibility migration:
-- 1. Legacy anon policies on public.service_requests.
-- 2. public.task_access_tokens remains backend-only.
-- 3. Task status changes continue through authenticated RPC functions.
