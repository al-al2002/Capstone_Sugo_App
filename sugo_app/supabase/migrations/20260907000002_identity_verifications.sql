-- SUGO: mandatory ID + selfie verification, for both roles
--
-- Replaces the two loose columns added in 20260906000004
-- (`profiles.id_document_url`, `profiles.id_submitted_at`) with a proper
-- submission record, because verification now has things those columns cannot
-- express: a second image, a review verdict, a reviewer's notes, a rejection
-- the user must respond to, and a history of attempts.
--
-- The old columns are deliberately left in place and kept in step by a trigger
-- (section 5), the same compatibility approach 20260906000004 took with
-- `technicians.id_document_url`. Anything still reading them keeps working.

-- ---------------------------------------------------------------------------
-- 1. The submission record
-- ---------------------------------------------------------------------------
--
-- One row per *attempt*, not one per user. A rejected submission is kept and a
-- new row is inserted for the retake, so the reviewer can see that this is a
-- third attempt and read why the first two failed. Overwriting in place would
-- destroy exactly the signal a fraud check depends on.
--
-- `role` is stored on the row rather than joined from `profiles` because it
-- records what the person was applying as *at submission time*. A technician
-- rejected on identity grounds who later re-registers as a client should not
-- have their old technician submission silently relabelled.

create table if not exists public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('technician', 'client')),

  -- Object paths in the private `identity-documents` bucket, NOT public URLs.
  -- Both are `not null`: the whole premise of this table is that a submission
  -- without a selfie is not a submission. The database refuses to store a
  -- half-submission rather than trusting the app to enforce it.
  id_document_url text not null,
  selfie_with_id_url text not null,

  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),

  -- Why a reviewer rejected it. Shown verbatim to the user on the retake
  -- prompt, so it must be written as something they can act on
  -- ("the ID in the selfie is not legible"), not an internal note.
  admin_notes text,

  reviewed_by uuid references public.profiles(id),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz
);

comment on table public.identity_verifications is
  'One row per ID + selfie submission attempt, for technicians and clients '
  'alike. Rejected attempts are retained so a reviewer sees the history.';

-- The reviewer queue: oldest pending first.
create index if not exists idx_identity_verifications_pending
  on public.identity_verifications (submitted_at)
  where status = 'pending';

-- "Show me this user's attempts, newest first" - the app's own lookup.
create index if not exists idx_identity_verifications_user
  on public.identity_verifications (user_id, submitted_at desc);

-- At most one submission may be awaiting review per user. Without this, tapping
-- submit twice on a slow connection files two identical attempts and a reviewer
-- has to approve or reject both. A partial unique index enforces it for
-- `pending` rows only, leaving any number of historical approved/rejected rows.
create unique index if not exists uniq_identity_verification_pending
  on public.identity_verifications (user_id)
  where status = 'pending';

-- ---------------------------------------------------------------------------
-- 2. Row level security
-- ---------------------------------------------------------------------------

alter table public.identity_verifications enable row level security;

-- A user reads their own attempts - the flow has to show "rejected, here's why".
drop policy if exists "identity_verifications_select_own" on public.identity_verifications;
create policy "identity_verifications_select_own"
  on public.identity_verifications for select to authenticated
  using (user_id = auth.uid());

-- A user files their own submission, and may only file it as `pending`.
--
-- The `status = 'pending'` term in the WITH CHECK is the important half. A
-- policy of `with check (user_id = auth.uid())` alone would let anyone insert
-- a row that is already `approved`, self-certifying in a single statement.
drop policy if exists "identity_verifications_insert_own" on public.identity_verifications;
create policy "identity_verifications_insert_own"
  on public.identity_verifications for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');

-- There is deliberately no UPDATE or DELETE policy for `authenticated`.
--
-- A user must not be able to edit a submission after filing it, withdraw a
-- rejection, or clear a reviewer's notes. Reviews are written by the service
-- role through `review_identity_verification()` below, which bypasses RLS.
-- Retaking means inserting a new attempt, which the insert policy allows.

-- ---------------------------------------------------------------------------
-- 3. Selfie storage
-- ---------------------------------------------------------------------------
--
-- Reuses the private `identity-documents` bucket from 20260906000004 rather
-- than adding a second one. A selfie holding a government ID is exactly as
-- sensitive as the ID itself - it contains the same document plus a face - so
-- it belongs under the same policies, and those policies already scope writes
-- to a folder named after the uploader's uid.
--
-- No new bucket, no new policies. This block only widens the size cap, because
-- a selfie is a camera capture rather than a scan and 5 MB was being hit by
-- modern phone cameras before compression.

update storage.buckets
set file_size_limit = 10485760  -- 10 MB
where id = 'identity-documents';

-- ---------------------------------------------------------------------------
-- 4. The reviewer's entry point
-- ---------------------------------------------------------------------------
--
-- Approving an identity has to touch two tables at once: the verification row
-- gets its verdict, and `profiles.registration_status` moves to `active` or
-- `rejected`. Done as two statements from the admin panel, a failure between
-- them leaves an approved ID attached to an account still stuck in review.
--
-- SECURITY DEFINER and service-role-only, for the same reason
-- `guard_registration_status` exists: this function is the *only* legitimate
-- way to reach `active`, so it must not be callable by the account it judges.

create or replace function public.review_identity_verification(
  p_verification_id uuid,
  p_approved boolean,
  p_reviewer_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid;
  v_role text;
  v_now timestamptz := now();
  v_new_status text;
begin
  select user_id, role into v_user_id, v_role
  from public.identity_verifications
  where id = p_verification_id
  for update;

  if v_user_id is null then
    raise exception 'No such identity verification: %', p_verification_id;
  end if;

  if not p_approved and coalesce(trim(p_notes), '') = '' then
    -- A rejection with no reason is unusable: the retake screen has nothing to
    -- tell the user, so they resubmit the same photos and are rejected again.
    raise exception 'A rejection must include a reason for the applicant';
  end if;

  update public.identity_verifications
  set status = case when p_approved then 'approved' else 'rejected' end,
      admin_notes = p_notes,
      reviewed_by = p_reviewer_id,
      reviewed_at = v_now
  where id = p_verification_id;

  -- A technician needs more than identity before they can trade: a passed
  -- assessment and a verified specialisation. Approving their ID therefore
  -- clears identity only, and `technicians.is_verified` stays where it is -
  -- 20260907000003 owns that decision. A client has nothing else outstanding,
  -- so an approved ID activates them outright.
  if p_approved then
    v_new_status := case when v_role = 'client' then 'active' else 'pending_review' end;
  else
    v_new_status := 'rejected';
  end if;

  update public.profiles
  set registration_status = v_new_status,
      onboarding_completed_at = case
        when p_approved and v_role = 'client'
        then coalesce(onboarding_completed_at, v_now)
        else onboarding_completed_at
      end
  where id = v_user_id;

  return jsonb_build_object(
    'user_id', v_user_id,
    'role', v_role,
    'approved', p_approved,
    'registration_status', v_new_status,
    'reviewed_at', v_now
  );
end;
$function$;

revoke all on function public.review_identity_verification(uuid, boolean, uuid, text)
  from public, anon, authenticated;
grant execute on function public.review_identity_verification(uuid, boolean, uuid, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 5. Keep the legacy columns in step
-- ---------------------------------------------------------------------------
--
-- `profiles.id_document_url` and `technicians.id_document_url` are read by
-- `SessionProfile.hasSubmittedId` and by the technician onboarding gate. Rather
-- than hunt down every reader in one go, this trigger mirrors each new
-- submission onto them, so old and new agree and the old readers keep working
-- until they are migrated.

create or replace function public.mirror_identity_document()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  update public.profiles
  set id_document_url = new.id_document_url,
      id_submitted_at = new.submitted_at
  where id = new.user_id;

  if new.role = 'technician' then
    update public.technicians
    set id_document_url = new.id_document_url,
        id_submitted_at = new.submitted_at
    where id = new.user_id;
  end if;

  return new;
end;
$function$;

drop trigger if exists identity_verifications_mirror on public.identity_verifications;
create trigger identity_verifications_mirror
  after insert on public.identity_verifications
  for each row execute function public.mirror_identity_document();

-- ---------------------------------------------------------------------------
-- 6. The queue an admin actually reads
-- ---------------------------------------------------------------------------
--
-- A view rather than a query embedded in the Laravel admin panel, so the
-- definition of "waiting for review" lives in one auditable place.
--
-- The image columns are object paths, not URLs. The reviewer's client has to
-- mint a short-lived signed URL for each - an identity document must never be
-- reachable from a link that outlives the review session.

create or replace view public.identity_review_queue as
select
  iv.id                as verification_id,
  iv.user_id,
  iv.role,
  iv.id_document_url,
  iv.selfie_with_id_url,
  iv.submitted_at,
  p.full_name,
  p.phone,
  p.registration_status,
  (
    select count(*)
    from public.identity_verifications prior
    where prior.user_id = iv.user_id
      and prior.submitted_at < iv.submitted_at
  ) + 1                as attempt_number,
  now() - iv.submitted_at as waiting_for
from public.identity_verifications iv
join public.profiles p on p.id = iv.user_id
where iv.status = 'pending'
order by iv.submitted_at;

comment on view public.identity_review_queue is
  'Pending ID + selfie submissions, oldest first, with the applicant''s '
  'attempt number so a reviewer can spot repeat rejections.';

revoke all on public.identity_review_queue from anon, authenticated;
grant select on public.identity_review_queue to service_role;
