-- SUGO: resumable registration and the account status machine
--
-- ## What this migration reverses, and why
--
-- 20260906000006_defer_profile_creation.sql made registration all-or-nothing:
-- the `on_auth_user_created` trigger was dropped, nothing was written to the
-- `public` schema until `complete_registration()` ran, and the documented
-- consequence was that a half-finished registration could not be resumed.
--
-- Mandatory ID + selfie verification changes the calculation. That flow is
-- long - account info, ID, selfie, specialisations, an assessment, document
-- uploads, a map pin - and it now ends in a human review queue rather than an
-- instant pass. Requiring someone to redo all of it because their phone rang
-- is not defensible, and the brief asks for an explicit `incomplete` account
-- status, which an absent row cannot express.
--
-- So partial state comes back, but it is now *labelled* rather than implied:
--
--   incomplete      registration started, mandatory ID + selfie not submitted
--   pending_review  everything required submitted, waiting on an admin
--   active          an admin approved it; the account can trade
--   rejected        an admin refused it; see identity_verifications.admin_notes
--
-- The cleanup story that motivated 000006 survives intact - it just keys off a
-- column instead of an absence. See section 4.

-- ---------------------------------------------------------------------------
-- 1. The status column
-- ---------------------------------------------------------------------------
--
-- `text` with a check constraint rather than a Postgres `enum`, matching
-- `profiles.role`, `technicians.tier` and every other categorical column in
-- this schema. The reason is operational: adding a value to a Postgres enum
-- could not run inside a transaction block before PG12 and still cannot be
-- rolled back cleanly, whereas widening a check constraint is an ordinary
-- transactional DDL statement. Given the review states here are likely to grow
-- (`expired`, `resubmit_requested`), the check constraint is the safer shape.
--
-- Defaults to 'incomplete': a row now exists from the moment of sign-up, and
-- the honest description of an account at that instant is "started, finished
-- nothing".

alter table public.profiles
  add column if not exists registration_status text not null default 'incomplete';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_registration_status_check'
  ) then
    alter table public.profiles
      add constraint profiles_registration_status_check
      check (registration_status in ('incomplete', 'pending_review', 'active', 'rejected'));
  end if;
end $$;

comment on column public.profiles.registration_status is
  'incomplete -> pending_review -> active | rejected. Only an admin moves a '
  'row out of pending_review; the app can never set active itself.';

-- Where to drop the user back into the stepper when they return.
--
-- Stored rather than derived. It *could* be recomputed - "no identity row means
-- the ID step, no specialisations means the specialisation step" - but that
-- rule would then exist twice, once here and once in the Flutter controller,
-- and the two would drift the first time a step was reordered. One stored
-- string, written by the client that owns the flow, keeps it single-sourced.
alter table public.profiles
  add column if not exists registration_step text;

comment on column public.profiles.registration_step is
  'Last completed step of the onboarding stepper, so "save and continue '
  'later" can resume in the right place. Null means nothing past account info.';

-- Existing accounts predate this column and are already trading. Marking them
-- 'active' rather than leaving them 'incomplete' prevents the new gate from
-- locking out everyone who registered under the old flow.
update public.profiles
set registration_status = 'active'
where onboarding_completed_at is not null
  and registration_status = 'incomplete';

create index if not exists idx_profiles_registration_status
  on public.profiles (registration_status);

-- The admin review queue reads this constantly: "oldest pending first".
create index if not exists idx_profiles_pending_review
  on public.profiles (created_at)
  where registration_status = 'pending_review';

-- ---------------------------------------------------------------------------
-- 2. Restore profile-on-signup
-- ---------------------------------------------------------------------------
--
-- `handle_new_user()` was left in place by 000006 precisely so this could be
-- undone with one statement. It is redefined here only to set the new status
-- column explicitly - relying on the column default would work today, but
-- would silently produce the wrong value if that default is ever changed.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.profiles (
    id, full_name, phone, avatar_url, role, registration_status
  )
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
    -- Unchanged from 20260905000002: anything other than an explicit
    -- 'technician' is treated as a client, so malformed or hostile metadata
    -- cannot mint a technician account.
    case
      when new.raw_user_meta_data ->> 'role' = 'technician' then 'technician'
      else 'client'
    end,
    'incomplete'
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;

comment on function public.handle_new_user() is
  'Creates the profile row at sign-up so registration can be resumed. '
  'Re-attached to auth.users in 20260907000001, reversing 20260906000006.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill: every auth account orphaned while 000006 was in force. Without
-- this they can log in but have no profile, and the app would treat them as a
-- brand-new signup forever.
insert into public.profiles (id, full_name, phone, role, registration_status)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name'),
  coalesce(u.raw_user_meta_data ->> 'phone', u.phone),
  case when u.raw_user_meta_data ->> 'role' = 'technician' then 'technician'
       else 'client' end,
  'incomplete'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Status transitions are not the client's to make
-- ---------------------------------------------------------------------------
--
-- WHY THIS TRIGGER EXISTS. `profiles` has had an owner-update policy since
-- 20260904000001:
--
--   create policy "Profiles are updatable by their owner"
--     on public.profiles for update using (auth.uid() = id);
--
-- Like the `technicians` policy that needed the same treatment in
-- 20260905000002, it checks *which row* may be written, never *which column*.
-- Adding `registration_status` to a table with that policy hands every user
-- this statement:
--
--   update profiles set registration_status = 'active' where id = auth.uid();
--
-- They would approve their own identity documents and skip review entirely,
-- which defeats the entire point of mandatory verification. Since the whole
-- feature is "a human checks the ID before the account trades", letting the
-- account self-certify would be the single worst bug in this migration.
--
-- The rule enforced below: a user may move themselves *forward* out of
-- 'incomplete' into 'pending_review' and nothing else. Reaching 'active' or
-- 'rejected' requires the service role, which has a null auth.uid() and
-- passes straight through.

create or replace function public.guard_registration_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  -- Service role, edge functions and pg_cron have no auth.uid(). They are the
  -- trusted callers and are exempt.
  if auth.uid() is null or auth.uid() <> new.id then
    return new;
  end if;

  if new.registration_status is distinct from old.registration_status then
    if not (
      old.registration_status = 'incomplete'
      and new.registration_status = 'pending_review'
    ) then
      raise exception
        'An account cannot change its own registration status from % to %',
        old.registration_status, new.registration_status;
    end if;
  end if;

  -- `onboarding_completed_at` is the other half of the same gate: it is what
  -- the old router read to decide an account was finished. Freezing the status
  -- but leaving this writable would just move the hole.
  if new.onboarding_completed_at is distinct from old.onboarding_completed_at
     and old.onboarding_completed_at is not null then
    raise exception 'Completion time is set once and cannot be rewritten';
  end if;

  -- Role is chosen once. Flipping it after review would carry an approved
  -- client's verification over to a technician account that was never assessed.
  if new.role is distinct from old.role
     and old.registration_status in ('pending_review', 'active') then
    raise exception 'Role cannot change after registration is submitted';
  end if;

  return new;
end;
$function$;

drop trigger if exists profiles_guard_registration_status on public.profiles;
create trigger profiles_guard_registration_status
  before update on public.profiles
  for each row execute function public.guard_registration_status();

-- ---------------------------------------------------------------------------
-- 4. Cleanup, rebuilt on the status column
-- ---------------------------------------------------------------------------
--
-- 000006 defined an abandoned signup as "an auth.users row with no profile".
-- That definition is now always empty, because the trigger in section 2
-- guarantees a profile. Restated against the status column it still selects
-- exactly the same people.
--
-- Note what is deliberately NOT filtered here, carried over unchanged from
-- 20260906000005: nothing checks `jobs`, `job_matches` or `job_outcomes`.
-- Those foreign keys have no `on delete cascade`, so Postgres itself refuses
-- to delete an account with real marketplace activity. A delete that fails
-- loudly beats a WHERE clause we might one day get wrong.

drop view if exists public.incomplete_signups;

create or replace view public.incomplete_signups as
select
  p.id,
  u.email,
  p.full_name,
  p.role,
  p.registration_status,
  p.registration_step,
  p.created_at,
  u.last_sign_in_at,
  now() - p.created_at as age
from public.profiles p
join auth.users u on u.id = p.id
where p.registration_status = 'incomplete';

comment on view public.incomplete_signups is
  'Accounts that never submitted mandatory ID verification. Read by '
  'purge-abandoned-signups. Accounts in pending_review are NOT here - '
  'someone waiting on an admin has done nothing wrong and must not be swept.';

revoke all on public.incomplete_signups from anon, authenticated;
grant select on public.incomplete_signups to service_role;

-- ---------------------------------------------------------------------------
-- 5. Stop the old commit path auto-verifying accounts
-- ---------------------------------------------------------------------------
--
-- `complete_registration()` from 000006 wrote the profile, the technician row
-- and a passing assessment in one transaction, and set `is_verified = true`
-- straight from a quiz score. Under mandatory ID review that last part is now
-- wrong on its own terms: passing a quiz proves competence, not identity, and
-- only an admin may activate an account.
--
-- WHY IT IS REDEFINED RATHER THAN DROPPED. The `complete-registration` edge
-- function still calls it, and the older registration flow still calls that.
-- Dropping it would leave a dangling reference that fails at runtime, on a
-- path that currently works. Redefining it with the same signature keeps that
-- caller working while bringing its behaviour in line: the account now lands
-- in `pending_review` instead of going live.
--
-- The two differences from the 000006 version:
--
--   * `is_verified` is left false. A human sets it, via
--     `review_identity_verification()` in 20260907000002.
--   * `onboarding_completed_at` is no longer stamped here. It means "cleared
--     to trade", which is now an admin's call rather than a quiz's.
--
-- New code should call `submit_registration_for_review()` from
-- 20260907000003 instead. This exists for the flow that predates it.

create or replace function public.complete_registration(
  p_user_id uuid,
  p_role text,
  p_full_name text,
  p_phone text,
  p_id_document_url text,
  p_specialization text default null,
  p_answers jsonb default null,
  p_score numeric default null,
  p_total_questions integer default null,
  p_tier text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_now timestamptz := now();
begin
  if p_role not in ('client', 'technician') then
    raise exception 'Invalid role: %', p_role;
  end if;

  if p_id_document_url is null or length(p_id_document_url) = 0 then
    raise exception 'An identity document is required';
  end if;

  insert into public.profiles (
    id, full_name, phone, role, role_chosen_at,
    id_document_url, id_submitted_at, registration_status, registration_step
  )
  values (
    p_user_id, p_full_name, p_phone, p_role, v_now,
    p_id_document_url, v_now, 'pending_review', 'review'
  )
  on conflict (id) do update
    set full_name = coalesce(excluded.full_name, public.profiles.full_name),
        phone = coalesce(excluded.phone, public.profiles.phone),
        role = excluded.role,
        role_chosen_at = coalesce(public.profiles.role_chosen_at, v_now),
        id_document_url = excluded.id_document_url,
        id_submitted_at = v_now,
        -- An account an admin already activated must not be knocked back to
        -- pending by a later call.
        registration_status = case
          when public.profiles.registration_status = 'active' then 'active'
          else 'pending_review'
        end,
        registration_step = 'review';

  if p_role = 'client' then
    return jsonb_build_object(
      'role', 'client',
      'registration_status', 'pending_review',
      'completed_at', v_now
    );
  end if;

  if p_specialization is null then
    raise exception 'A specialisation is required for technicians';
  end if;

  insert into public.technicians (
    id, specialization, tier, is_verified, is_available,
    id_document_url, id_submitted_at
  )
  values (
    p_user_id, array[p_specialization], coalesce(p_tier, 'standard'),
    false,  -- NOT auto-verified any more. An admin decides.
    false,
    p_id_document_url, v_now
  )
  on conflict (id) do update
    set specialization = excluded.specialization,
        tier = coalesce(excluded.tier, public.technicians.tier),
        id_document_url = excluded.id_document_url,
        id_submitted_at = v_now;

  insert into public.technician_assessments (
    technician_id, specialization, answers, score,
    total_questions, passed, suggested_tier
  )
  values (
    p_user_id, p_specialization, coalesce(p_answers, '{}'::jsonb),
    coalesce(p_score, 0), coalesce(p_total_questions, 0), true, p_tier
  );

  return jsonb_build_object(
    'role', 'technician',
    'tier', p_tier,
    'registration_status', 'pending_review',
    'completed_at', v_now
  );
end;
$function$;

revoke all on function public.complete_registration(
  uuid, text, text, text, text, text, jsonb, numeric, integer, text
) from public, anon, authenticated;

grant execute on function public.complete_registration(
  uuid, text, text, text, text, text, jsonb, numeric, integer, text
) to service_role;
