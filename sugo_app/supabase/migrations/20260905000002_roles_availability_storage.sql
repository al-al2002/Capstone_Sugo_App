-- SUGO: account roles, technician availability, and the job-photos bucket
--
-- Three things the dashboards need that the earlier migrations did not provide.
--
--   1. profiles.role          - decides which dashboard a user lands on
--   2. technicians.is_available - the online/offline toggle
--   3. the `job-photos` bucket - where job photos actually go
--
-- Plus one security fix that becomes necessary the moment a technician can
-- update their own row from the UI. See section 4.

-- ---------------------------------------------------------------------------
-- 1. profiles.role
-- ---------------------------------------------------------------------------
--
-- The routing rule is "read profiles.role, send them to the matching
-- dashboard". That column did not exist, so it is added here rather than
-- inferred from whether a `technicians` row happens to exist - inference
-- breaks for a technician who has signed up but not finished onboarding, which
-- is exactly the case the router has to handle.
--
-- Defaults to 'client': every existing account predates the technician flow,
-- and a client dashboard is the safe landing place for an unknown account.

alter table public.profiles
  add column if not exists role text not null default 'client';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_role_check'
  ) then
    alter table public.profiles
      add constraint profiles_role_check
      check (role in ('client', 'technician'));
  end if;
end $$;

comment on column public.profiles.role is
  'Which dashboard this account lands on after login: client or technician.';

create index if not exists idx_profiles_role on public.profiles (role);

-- Carry the role through sign-up. The Flutter register form puts it in
-- raw_user_meta_data; this replaces the trigger function from the profiles
-- migration so the value is not lost. Everything else about it is unchanged.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.profiles (id, full_name, phone, avatar_url, role)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    ),
    coalesce(new.raw_user_meta_data ->> 'phone', new.phone),
    coalesce(
      new.raw_user_meta_data ->> 'avatar_url',
      new.raw_user_meta_data ->> 'picture'
    ),
    -- Anything other than an explicit 'technician' is treated as a client, so
    -- a malformed or hostile metadata value cannot mint a technician account.
    case
      when new.raw_user_meta_data ->> 'role' = 'technician' then 'technician'
      else 'client'
    end
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. technicians.is_available
-- ---------------------------------------------------------------------------
--
-- The online/offline switch on the technician dashboard. Defaults to false so
-- a newly verified technician is offline until they deliberately go online -
-- opting in beats being opted in.
--
-- This is separate from `is_verified` and from `current_workload`, and all
-- three gate the matching pool differently:
--
--   is_verified      - permanent, set by SUGO staff. Are they allowed to work?
--   is_available     - momentary, set by the technician. Are they online now?
--   current_workload - derived from active jobs. How busy are they?

alter table public.technicians
  add column if not exists is_available boolean not null default false;

comment on column public.technicians.is_available is
  'Technician-controlled online/offline switch. Matching skips offline rows.';

-- Partial index: the matcher only ever asks for verified AND available rows,
-- so indexing just that subset keeps it small.
create index if not exists idx_technicians_available
  on public.technicians (is_available)
  where is_verified = true;

-- ---------------------------------------------------------------------------
-- 3. Storage bucket for job photos
-- ---------------------------------------------------------------------------
--
-- `RbCarsService.uploadPhotos` writes to `job-photos/<uid>/<timestamp>_<n>.<ext>`.
-- Public read, because the matched technician has to see the photo of the
-- broken device and they are not the client who uploaded it.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'job-photos',
  'job-photos',
  true,
  5242880,  -- 5 MB per file; the picker already downscales to 1600px at q80
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- A signed-in user may only write inside a folder named after their own uid.
-- `storage.foldername(name)` splits the object path, so element 1 is the first
-- segment - the uid the service builds the path from.
drop policy if exists "job_photos_insert_own_folder" on storage.objects;
create policy "job_photos_insert_own_folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'job-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "job_photos_update_own_folder" on storage.objects;
create policy "job_photos_update_own_folder"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'job-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "job_photos_delete_own_folder" on storage.objects;
create policy "job_photos_delete_own_folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'job-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Read is open, matching the public bucket. Anyone with the URL can view a
-- photo; nobody can list, overwrite or delete someone else's.
drop policy if exists "job_photos_public_read" on storage.objects;
create policy "job_photos_public_read"
  on storage.objects for select
  using (bucket_id = 'job-photos');

-- ---------------------------------------------------------------------------
-- 4. Privilege-escalation guard on technicians
-- ---------------------------------------------------------------------------
--
-- WHY THIS IS HERE. The RB-CARS migration granted:
--
--   create policy "technicians_update_own" on technicians for update
--     using (id = auth.uid());
--
-- That policy checks *which row* may be updated, never *which columns*. Until
-- now nothing in the app used it, so it was harmless. This migration adds
-- `is_available`, which the dashboard toggle writes directly - and the moment
-- that write path exists, the same policy lets a technician run:
--
--   update technicians set is_verified = true, tier = 'elite', rating = 5
--   where id = auth.uid();
--
-- They would self-verify, promote themselves to the top tier, and jump the
-- Stage 1 ranking. That defeats the verification gate and the whole feedback
-- loop.
--
-- This trigger closes it. A technician may edit only the fields that describe
-- their own work - skills, specialisation, location, availability. Everything
-- that SUGO awards or the system computes is frozen against direct updates and
-- can only change through an edge function on the service role, which bypasses
-- RLS and therefore this trigger's `auth.uid()` check.

create or replace function public.guard_technician_self_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  -- auth.uid() is null for the service role and for pg_cron, so trusted
  -- server-side callers pass straight through.
  if auth.uid() is null or auth.uid() <> new.id then
    return new;
  end if;

  if new.is_verified is distinct from old.is_verified then
    raise exception 'A technician cannot change their own verification status';
  end if;

  if new.tier is distinct from old.tier then
    raise exception 'A technician cannot change their own tier';
  end if;

  if new.badge is distinct from old.badge then
    raise exception 'A technician cannot change their own badge';
  end if;

  if new.rating is distinct from old.rating then
    raise exception 'Rating is computed from job outcomes, not set by hand';
  end if;

  if new.total_jobs is distinct from old.total_jobs then
    raise exception 'Job count is computed from job outcomes, not set by hand';
  end if;

  if new.current_workload is distinct from old.current_workload then
    raise exception 'Workload is maintained by the booking flow';
  end if;

  return new;
end;
$function$;

drop trigger if exists technicians_guard_self_update on public.technicians;
create trigger technicians_guard_self_update
  before update on public.technicians
  for each row execute function public.guard_technician_self_update();
