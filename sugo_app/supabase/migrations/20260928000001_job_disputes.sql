-- =============================================================================
-- SUGO: disputes - "Report a problem with this booking"
-- =============================================================================
--
-- Either side of a job can report that something went wrong with it - the
-- repair did not hold, the price was not what was agreed, somebody did not
-- turn up, something was damaged - and a SUGO admin reviews it and records a
-- decision both sides can read.
--
-- ## A new table, with approval
--
-- Asked first, as the schema is otherwise frozen (see the RB-CARS notes): the
-- client approved `job_disputes` on 2026-09-28. The four RB-CARS tables are
-- untouched. A column on `jobs` was not enough: a job can collect a report
-- from each side, each with its own words, photos and outcome.
--
-- ## Who can do what
--
-- | Who                         | Can                                      |
-- |-----------------------------|------------------------------------------|
-- | client of the job           | open a report, read reports on the job   |
-- | the ASSIGNED technician     | open a report, read reports on the job   |
-- | an offered-only technician  | nothing - they never had the job         |
-- | an admin (service role)     | read all, decide via resolve_job_dispute |
--
-- Deliberately stricter than `is_job_participant()`, which since 20260923000003
-- also admits a technician who has only been *offered* the job so they can
-- negotiate in chat. Nobody can dispute a job they never did.
--
-- There are no insert, update or delete policies. Opening goes through
-- `open_job_dispute()`, which checks the rules below; deciding goes through
-- `resolve_job_dispute()`, which only the service role may call. A report
-- cannot be edited or withdrawn once sent - like the chat log, it is the
-- record.
--
-- ## When a report can be opened
--
-- Once a technician has taken the job (confirmed or in progress), and for
-- seven days after it is completed. After that the repair has had a week to
-- fail, and a report is for support to handle by email instead.
--
-- ## After applying this
--
--   supabase db push
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------------

create table if not exists public.job_disputes (
  id              uuid primary key default gen_random_uuid(),
  job_id          uuid not null references public.jobs(id) on delete cascade,
  raised_by       uuid not null references public.profiles(id) on delete cascade,
  raised_by_role  text not null check (raised_by_role in ('client', 'technician')),

  -- A fixed list, so the admin queue can be filtered and counted, and so
  -- the app can offer each side only the reasons that make sense for it.
  reason          text not null check (reason in (
                    'not_fixed', 'overcharged', 'no_show', 'damage',
                    'conduct', 'payment', 'other'
                  )),
  details         text not null
                    check (length(trim(details)) between 10 and 2000),

  -- Paths inside the private `dispute-photos` bucket, `<job_id>/<uuid>`.
  photo_paths     text[] not null default '{}'
                    check (cardinality(photo_paths) <= 4),

  status          text not null default 'open'
                    check (status in ('open', 'resolved', 'dismissed')),

  -- The admin's decision, shown word for word to both sides.
  resolution_note text check (resolution_note is null
                              or length(resolution_note) <= 2000),
  resolved_by     uuid references public.profiles(id),
  resolved_at     timestamptz,
  created_at      timestamptz not null default now(),

  constraint job_disputes_decided_consistently check (
    (status = 'open' and resolved_at is null)
    or (status <> 'open' and resolved_at is not null
        and length(trim(coalesce(resolution_note, ''))) > 0)
  )
);

comment on table public.job_disputes is
  'Problems reported on a job by its client or assigned technician, and the '
  'admin''s decision. Written only through open_job_dispute() and '
  'resolve_job_dispute().';

-- One open report per person per job: a second tap does not file a second
-- case. Once decided, the same person may report again.
create unique index if not exists job_disputes_one_open_per_party
  on public.job_disputes (job_id, raised_by)
  where status = 'open';

create index if not exists job_disputes_queue
  on public.job_disputes (status, created_at desc);

create index if not exists job_disputes_job
  on public.job_disputes (job_id);

-- ---------------------------------------------------------------------------
-- 2. Reading
-- ---------------------------------------------------------------------------

alter table public.job_disputes enable row level security;

-- The two people who did the job see every report on it - including the one
-- about them. A report the accused cannot read is not a fair process, and
-- the reply belongs in the chat, which the admin reads too.
drop policy if exists "job_disputes_select_party" on public.job_disputes;
create policy "job_disputes_select_party"
  on public.job_disputes for select to authenticated
  using (
    exists (
      select 1 from public.jobs j
      where j.id = job_disputes.job_id
        and (j.client_id = auth.uid() or j.assigned_technician_id = auth.uid())
    )
  );

revoke all on table public.job_disputes from anon;
grant select on public.job_disputes to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Opening a report
-- ---------------------------------------------------------------------------

create or replace function public.open_job_dispute(
  p_job_id      uuid,
  p_reason      text,
  p_details     text,
  p_photo_paths text[] default '{}'
)
returns public.job_disputes
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid       uuid := auth.uid();
  v_job       public.jobs%rowtype;
  v_role      text;
  v_completed timestamptz;
  v_path      text;
  v_row       public.job_disputes%rowtype;
begin
  if v_uid is null then
    raise exception 'Sign in to report a problem.';
  end if;

  select * into v_job from public.jobs where id = p_job_id;
  if not found then
    raise exception 'That booking could not be found.';
  end if;

  if v_job.client_id = v_uid then
    v_role := 'client';
  elsif v_job.assigned_technician_id = v_uid then
    v_role := 'technician';
  else
    raise exception 'Only the client and the technician on this booking can report a problem with it.';
  end if;

  if v_job.assigned_technician_id is null
     or v_job.status not in ('confirmed', 'in_progress', 'completed') then
    raise exception 'A problem can be reported once a technician has taken the booking.';
  end if;

  if v_job.status = 'completed' then
    select max(created_at) into v_completed
    from public.job_outcomes where job_id = p_job_id;

    if v_completed is not null and v_completed < now() - interval '7 days' then
      raise exception 'Reports close 7 days after a booking is completed. Contact SUGO support instead.';
    end if;
  end if;

  if exists (
    select 1 from public.job_disputes
    where job_id = p_job_id and raised_by = v_uid and status = 'open'
  ) then
    raise exception 'You already reported a problem with this booking. SUGO is reviewing it.';
  end if;

  -- Photos must have been uploaded into this job's folder - so nobody can
  -- attach a file from somebody else's case.
  foreach v_path in array coalesce(p_photo_paths, '{}') loop
    if split_part(v_path, '/', 1) <> p_job_id::text then
      raise exception 'A photo does not belong to this booking.';
    end if;
  end loop;

  insert into public.job_disputes (
    job_id, raised_by, raised_by_role, reason, details, photo_paths
  ) values (
    p_job_id, v_uid, v_role, p_reason, trim(p_details),
    coalesce(p_photo_paths, '{}')
  )
  returning * into v_row;

  return v_row;
end;
$function$;

comment on function public.open_job_dispute(uuid, text, text, text[]) is
  'Opens a report on a job for its client or assigned technician, once the '
  'job has been taken and until 7 days after completion. One open report per '
  'person per job.';

revoke all on function public.open_job_dispute(uuid, text, text, text[])
  from public, anon;
grant execute on function public.open_job_dispute(uuid, text, text, text[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Deciding a report (admin console only)
-- ---------------------------------------------------------------------------

create or replace function public.resolve_job_dispute(
  p_dispute_id uuid,
  p_decision   text,
  p_note       text,
  p_admin_id   uuid
)
returns public.job_disputes
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_row public.job_disputes%rowtype;
begin
  if p_decision not in ('resolved', 'dismissed') then
    raise exception 'A decision is either resolved or dismissed.';
  end if;

  if length(trim(coalesce(p_note, ''))) < 5 then
    raise exception 'Write the decision out - both sides are shown it word for word.';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_admin_id and role = 'admin'
  ) then
    raise exception 'Only an admin can decide a report.';
  end if;

  update public.job_disputes
  set status = p_decision,
      resolution_note = trim(p_note),
      resolved_by = p_admin_id,
      resolved_at = now()
  where id = p_dispute_id and status = 'open'
  returning * into v_row;

  if not found then
    raise exception 'That report was not found, or has already been decided.';
  end if;

  return v_row;
end;
$function$;

revoke all on function public.resolve_job_dispute(uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_job_dispute(uuid, text, text, uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 5. Photos
-- ---------------------------------------------------------------------------
--
-- PRIVATE, like `chat-photos`: evidence about two people, read by those two
-- and the admin (who signs URLs with the service role).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'dispute-photos',
  'dispute-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_access_dispute_photo(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_job uuid;
begin
  -- `name` is caller-supplied text: a malformed path is a refusal, not a 500.
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

grant execute on function public.can_access_dispute_photo(text) to authenticated;

drop policy if exists "dispute_photos_insert_party" on storage.objects;
create policy "dispute_photos_insert_party"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'dispute-photos'
    and public.can_access_dispute_photo(name)
  );

drop policy if exists "dispute_photos_select_party" on storage.objects;
create policy "dispute_photos_select_party"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'dispute-photos'
    and public.can_access_dispute_photo(name)
  );

-- No update or delete policy: evidence is not edited after it is sent.

-- ---------------------------------------------------------------------------
-- 6. The admin queue
-- ---------------------------------------------------------------------------
--
-- Service role only, like `admin_jobs`: it names both people and returns
-- every report on the platform.

create or replace view public.admin_disputes as
select
  d.id,
  d.job_id,
  d.created_at,
  d.status,
  d.reason,
  d.details,
  d.photo_paths,
  d.raised_by,
  d.raised_by_role,
  pr.full_name          as raised_by_name,
  d.resolution_note,
  d.resolved_at,
  pa.full_name          as resolved_by_name,
  j.device_type,
  j.brand,
  j.problem_symptom,
  j.status              as job_status,
  j.client_id,
  pc.full_name          as client_name,
  j.assigned_technician_id as technician_id,
  pt.full_name          as technician_name
from public.job_disputes d
join public.jobs j       on j.id = d.job_id
join public.profiles pr  on pr.id = d.raised_by
join public.profiles pc  on pc.id = j.client_id
left join public.profiles pt on pt.id = j.assigned_technician_id
left join public.profiles pa on pa.id = d.resolved_by;

revoke all on table public.admin_disputes from anon, authenticated;
grant select on public.admin_disputes to service_role;
