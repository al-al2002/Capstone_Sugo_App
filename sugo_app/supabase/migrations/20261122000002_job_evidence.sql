-- SUGO: in-task documentation - the work record (2026-11-22)
--
-- Approved by the user on 2026-11-22 ("go"), after a written proposal: a new
-- table, a private photo bucket, required checkpoints enforced by the server.
--
-- ## Why
--
-- Specific Objective 4 of the paper promises "a booking and workflow tracking
-- system with in-task documentation", and FR-11 "timestamped photos, text
-- updates, and location stamps during a task as proof of service delivery".
-- The disputes module (20260928000001) leans on that evidence. Until now it
-- did not exist: `job-response` carried a TODO for it.
--
-- ## What changes
--
-- 1. `job_evidence`: one row per checkpoint photo set. Rows are NEVER updated
--    or deleted - not even by the technician who took them - which is what
--    makes them evidence. `captured_at` is set by the database, so the time
--    cannot be typed in by the phone.
-- 2. Checkpoints (`milestone`):
--      intake     the unit as found: "Before" on a home visit, "Collected" on
--                 a pickup, "Unit received" on a drop-off      REQUIRED
--      diagnosis  e.g. the faulty part                         optional
--      progress   mid-repair                                   optional
--      after      repaired and working                         REQUIRED
--      handover   handed back (shop repairs)                   optional
--    `intake` must exist before `after` can be added.
-- 3. `add_job_evidence()` is the only way in: the assigned technician, while
--    the job is confirmed or in progress.
-- 4. `job_evidence_missing()` lists the required checkpoints still missing.
--    `job-response` refuses to complete a job while it is not empty, so an
--    old app build cannot skip it. Jobs POSTED before this migration was
--    applied are exempt (`job_evidence_cutoff()`), so nobody is stuck
--    mid-job.
-- 5. A PRIVATE bucket, `job-evidence`, `<job_id>/<file>`: written by the
--    assigned technician, read by the client and the technician on the job,
--    and by the admin (service role, signed URLs). No update or delete.

-- ---------------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------------

create table if not exists public.job_evidence (
  id                  uuid primary key default gen_random_uuid(),
  job_id              uuid not null references public.jobs (id) on delete cascade,
  technician_id       uuid not null references public.technicians (id),
  milestone           text not null
    check (milestone in ('intake', 'diagnosis', 'progress', 'after', 'handover')),
  photo_paths         text[] not null
    check (cardinality(photo_paths) between 1 and 4),
  note                text
    check (note is null or char_length(note) <= 500),
  -- The phone's GPS when the photos were added. Null when location was off:
  -- the record still counts, and the client is told it was not recorded.
  latitude            double precision
    check (latitude is null or latitude between -90 and 90),
  longitude           double precision
    check (longitude is null or longitude between -180 and 180),
  location_accuracy_m real,
  -- Set here, never by the app.
  captured_at         timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);

comment on table public.job_evidence is
  'In-task documentation: checkpoint photos a technician takes during a job '
  '(20261122000002). Never updated or deleted. Written only through '
  'add_job_evidence().';

create index if not exists job_evidence_job
  on public.job_evidence (job_id, captured_at);

-- ---------------------------------------------------------------------------
-- 2. Reading: the two people on the job (the admin uses the service role)
-- ---------------------------------------------------------------------------

alter table public.job_evidence enable row level security;

drop policy if exists "job_evidence_select_party" on public.job_evidence;
create policy "job_evidence_select_party"
  on public.job_evidence for select to authenticated
  using (
    exists (
      select 1 from public.jobs j
      where j.id = job_evidence.job_id
        and (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
    )
  );

revoke all on table public.job_evidence from anon;
grant select on public.job_evidence to authenticated;
-- No insert, update or delete policy: rows arrive only through
-- add_job_evidence(), and are never changed.

-- ---------------------------------------------------------------------------
-- 3. When the requirement started
-- ---------------------------------------------------------------------------
--
-- The moment this migration ran, frozen into a function. A job posted before
-- it is exempt from the required checkpoints - its technician may be halfway
-- through a repair with no photos, and must still be able to finish.

do $cutoff$
begin
  execute format(
    'create or replace function public.job_evidence_cutoff() '
    'returns timestamptz language sql immutable as $f$ select %L::timestamptz $f$',
    now()
  );
end;
$cutoff$;

comment on function public.job_evidence_cutoff() is
  'When in-task documentation became required. Jobs created before it are '
  'exempt from the required checkpoints.';

grant execute on function public.job_evidence_cutoff() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. What is still missing
-- ---------------------------------------------------------------------------

create or replace function public.job_evidence_missing(p_job_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid  uuid := auth.uid();
  v_job  public.jobs%rowtype;
  v_have text[];
begin
  select * into v_job from public.jobs where id = p_job_id;
  if not found then
    raise exception 'That booking could not be found.';
  end if;

  -- A signed-in caller must be on the job. No uid means the service role
  -- (`job-response`): anon cannot execute this function.
  if v_uid is not null
     and v_uid is distinct from v_job.client_id
     and v_uid is distinct from v_job.assigned_technician_id then
    raise exception 'Only the client and the technician on this booking can see its work record.';
  end if;

  -- A Technician Community question has no visit to document, and a job
  -- posted before the requirement is exempt.
  if coalesce(v_job.service_path, '') not in ('home_service', 'pickup')
     or v_job.created_at < public.job_evidence_cutoff() then
    return '{}';
  end if;

  select coalesce(array_agg(distinct milestone), '{}')
  into v_have
  from public.job_evidence
  where job_id = p_job_id;

  return array(
    select m from unnest(array['intake', 'after']) as m
    where not (m = any (v_have))
  );
end;
$function$;

comment on function public.job_evidence_missing(uuid) is
  'The required checkpoints (intake, after) not yet on a job''s work record. '
  'Empty when done, for a community question, or for a job posted before '
  'job_evidence_cutoff(). job-response refuses completion until it is empty.';

revoke all on function public.job_evidence_missing(uuid) from public, anon;
grant execute on function public.job_evidence_missing(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Adding a checkpoint
-- ---------------------------------------------------------------------------

create or replace function public.add_job_evidence(
  p_job_id      uuid,
  p_milestone   text,
  p_photo_paths text[],
  p_note        text default null,
  p_latitude    double precision default null,
  p_longitude   double precision default null,
  p_accuracy_m  real default null
)
returns public.job_evidence
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid  uuid := auth.uid();
  v_job  public.jobs%rowtype;
  v_path text;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_row  public.job_evidence%rowtype;
begin
  if v_uid is null then
    raise exception 'Sign in to add photos to the work record.';
  end if;

  select * into v_job from public.jobs where id = p_job_id;
  if not found then
    raise exception 'That booking could not be found.';
  end if;

  if v_job.assigned_technician_id is distinct from v_uid then
    raise exception 'Only the technician on this booking can add to its work record.';
  end if;

  if v_job.status not in ('confirmed', 'in_progress') then
    raise exception 'Photos can be added only while the job is under way.';
  end if;

  if p_milestone not in ('intake', 'diagnosis', 'progress', 'after', 'handover') then
    raise exception 'That is not a step of the work record.';
  end if;

  if p_milestone = 'after' and not exists (
    select 1 from public.job_evidence
    where job_id = p_job_id and milestone = 'intake'
  ) then
    raise exception 'Add the photo of the unit as you found it first.';
  end if;

  if coalesce(cardinality(p_photo_paths), 0) not between 1 and 4 then
    raise exception 'Add between 1 and 4 photos.';
  end if;

  -- Every photo must already be in this job's folder, so nobody can attach a
  -- file from another booking.
  foreach v_path in array p_photo_paths loop
    if split_part(v_path, '/', 1) <> p_job_id::text then
      raise exception 'A photo does not belong to this booking.';
    end if;
  end loop;

  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'Keep the note under 500 characters.';
  end if;

  insert into public.job_evidence (
    job_id, technician_id, milestone, photo_paths, note,
    latitude, longitude, location_accuracy_m
  ) values (
    p_job_id, v_uid, p_milestone, p_photo_paths, v_note,
    case when p_latitude is not null and p_longitude is not null then p_latitude end,
    case when p_latitude is not null and p_longitude is not null then p_longitude end,
    p_accuracy_m
  )
  returning * into v_row;

  return v_row;
end;
$function$;

comment on function public.add_job_evidence(uuid, text, text[], text, double precision, double precision, real) is
  'Adds one checkpoint to a job''s work record. Assigned technician only, '
  'while the job is confirmed or in progress; the unit-as-found checkpoint '
  'must come before "after".';

revoke all on function public.add_job_evidence(uuid, text, text[], text, double precision, double precision, real)
  from public, anon;
grant execute on function public.add_job_evidence(uuid, text, text[], text, double precision, double precision, real)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The photos
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'job-evidence',
  'job-evidence',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The job id is the first folder of the path. A malformed path is a refusal,
-- not an error.
create or replace function public.can_upload_job_evidence(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_job uuid;
begin
  begin
    v_job := (storage.foldername(p_name))[1]::uuid;
  exception when others then
    return false;
  end;

  return exists (
    select 1 from public.jobs j
    where j.id = v_job
      and j.assigned_technician_id = auth.uid()
      and j.status in ('confirmed', 'in_progress')
  );
end;
$function$;

create or replace function public.can_read_job_evidence(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_job uuid;
begin
  begin
    v_job := (storage.foldername(p_name))[1]::uuid;
  exception when others then
    return false;
  end;

  return exists (
    select 1 from public.jobs j
    where j.id = v_job
      and (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
  );
end;
$function$;

revoke all on function public.can_upload_job_evidence(text) from public, anon;
revoke all on function public.can_read_job_evidence(text) from public, anon;
grant execute on function public.can_upload_job_evidence(text) to authenticated;
grant execute on function public.can_read_job_evidence(text) to authenticated;

drop policy if exists "job_evidence_insert_technician" on storage.objects;
create policy "job_evidence_insert_technician"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'job-evidence'
    and public.can_upload_job_evidence(name)
  );

drop policy if exists "job_evidence_select_party" on storage.objects;
create policy "job_evidence_select_party"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'job-evidence'
    and public.can_read_job_evidence(name)
  );

-- No update or delete policy: evidence is not edited after it is taken.
