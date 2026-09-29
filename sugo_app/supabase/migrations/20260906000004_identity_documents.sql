-- SUGO: identity documents for both roles
--
-- Two changes driven by testing the onboarding flow on a device.
--
--   1. Clients now submit an ID too, so the columns move to `profiles`, which
--      both roles have. `technicians.id_document_url` stays for compatibility.
--   2. A single shared private bucket replaces `technician-ids`, and its MIME
--      allow-list is widened - the narrow list was rejecting real uploads.

-- ---------------------------------------------------------------------------
-- 1. ID columns on profiles
-- ---------------------------------------------------------------------------
--
-- Put on `profiles` rather than duplicated per role: a client has no
-- `technicians` row to hang them off, and identity is a property of the person
-- rather than of what they do on the platform.
--
-- The technician columns added in 20260906000001 are deliberately left in
-- place. Dropping them would break the rows already written, and the
-- onboarding service now writes both so the two stay in step.

alter table public.profiles
  add column if not exists id_document_url text;

alter table public.profiles
  add column if not exists id_submitted_at timestamptz;

comment on column public.profiles.id_document_url is
  'Object path in the identity-documents bucket. Not a public URL - the '
  'bucket is private and is read through short-lived signed URLs.';

-- ---------------------------------------------------------------------------
-- 2. One private bucket for both roles
-- ---------------------------------------------------------------------------
--
-- WHY THE MIME LIST IS WIDER. The previous bucket allowed only
-- `image/jpeg` and `image/png`. Supabase rejects an upload whose declared
-- content type is not on that list, and the content type is inferred from the
-- filename - so a picker that returns a `.jpeg`, a `.heic` from an iPhone, or a
-- file with no usable extension was refused with a 400 that surfaced as a
-- generic "could not upload" in the app.
--
-- The list below covers what the image pickers actually produce, and
-- `application/octet-stream` is included as the fallback a client sends when it
-- cannot determine a type. Size and format are still enforced client-side in
-- `OnboardingService.validateIdFile`, and the 5 MB bucket cap still applies.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'identity-documents',
  'identity-documents',
  false,
  5242880,
  array[
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/octet-stream'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Same widening for the old technician bucket, so anything already pointing at
-- it keeps working rather than failing in a second, different way.
update storage.buckets
set allowed_mime_types = array[
      'image/jpeg','image/jpg','image/png','image/webp',
      'image/heic','image/heif','application/octet-stream'
    ]
where id = 'technician-ids';

-- ---------------------------------------------------------------------------
-- 3. Policies: a user owns the folder named after their uid
-- ---------------------------------------------------------------------------

drop policy if exists "identity_documents_insert_own" on storage.objects;
create policy "identity_documents_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'identity-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "identity_documents_select_own" on storage.objects;
create policy "identity_documents_select_own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'identity-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Update is needed as well as insert: the app uploads with `upsert: true` so a
-- retry overwrites the previous attempt instead of littering the bucket, and
-- Postgres requires both policies for an upsert.
drop policy if exists "identity_documents_update_own" on storage.objects;
create policy "identity_documents_update_own"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'identity-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "identity_documents_delete_own" on storage.objects;
create policy "identity_documents_delete_own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'identity-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Note: there is deliberately no public read policy. An identity document must
-- never be readable from a guessable URL, which is the whole reason this bucket
-- is separate from the public `job-photos` one.
