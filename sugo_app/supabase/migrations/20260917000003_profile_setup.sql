-- SUGO: a one-time "set up your profile" step for newly approved accounts
--
-- ## What it is for
--
-- Registration proves who someone is and what they can do. It never asked for
-- two things the rest of the app now depends on:
--
--   * a profile PHOTO - every technician card, the profile screen and the
--     review list fall back to initials, for every account;
--   * a technician's WORKSHOP name and location - nothing in the app ever wrote
--     `technicians.shop_name`, `shop_latitude` or `shop_longitude`. The client
--     collection map and the in-app route (20260916000008, job-route) have been
--     falling back to the registered base address because there was no shop.
--
-- So the first time an approved account signs in, it is asked for these.
--
-- ## Why a timestamp and not a boolean
--
-- `profile_setup_completed_at` rather than `profile_setup_done`. Null means the
-- step is still owed; a time records when it was finished or skipped. It is the
-- same shape as `onboarding_completed_at`, which the router already reads.
--
-- ## Who sees it: only NEW approvals
--
-- Every account that is already `active` is marked complete here, so nobody
-- who was approved before this step existed is suddenly stopped at sign-in and
-- asked to redo their profile. Accounts that are still `incomplete`,
-- `pending_review` or `rejected` keep null - when they are approved later, they
-- are new approvals, and they get the step.
--
-- ## What it deliberately does NOT let anyone change
--
-- The name. `full_name` is what the ID review checked against the document; a
-- setup screen that let an approved account rename itself would undo the
-- verification it just passed. Photo and workshop are presentation and
-- logistics. The name is identity.

alter table public.profiles
  add column if not exists profile_setup_completed_at timestamptz;

comment on column public.profiles.profile_setup_completed_at is
  'When the account finished (or skipped) the one-time profile setup shown after '
  'approval. Null means it is still owed. Existing active accounts were marked '
  'complete when the step was introduced, so only new approvals see it.';

-- Backfill without touching `updated_at`. `profiles_touch_updated_at` would
-- otherwise stamp every active profile as edited today, which would be a false
-- record of when those people last changed anything.
alter table public.profiles disable trigger profiles_touch_updated_at;

update public.profiles
set profile_setup_completed_at = now()
where registration_status = 'active'
  and profile_setup_completed_at is null;

alter table public.profiles enable trigger profiles_touch_updated_at;

-- ---------------------------------------------------------------------------
-- Avatars
-- ---------------------------------------------------------------------------
--
-- Same layout and rules as `job-photos` in 20260905000002: one folder per user,
-- named by uid, writable only by that user.
--
-- Public read, because an avatar exists to be seen by OTHER people - a client
-- browsing technicians, a technician looking at who booked them. A private
-- bucket would mean signing every card's image URL.
--
-- 2 MB and images only. The screen downscales before upload, so a real photo is
-- well under this; the limit exists so the bucket cannot be used as free file
-- hosting through a hand-crafted request.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars_insert_own_folder" on storage.objects;
create policy "avatars_insert_own_folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Update is needed because a changed photo overwrites the same path.
drop policy if exists "avatars_update_own_folder" on storage.objects;
create policy "avatars_update_own_folder"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_delete_own_folder" on storage.objects;
create policy "avatars_delete_own_folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');
