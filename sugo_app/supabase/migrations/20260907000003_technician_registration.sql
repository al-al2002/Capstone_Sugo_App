-- SUGO: technician specialisations, per-specialisation assessment, documents
--
-- The existing technician model is one specialisation and one account-wide
-- tier: `technicians.specialization` is a text[] that the flow only ever put a
-- single value in, and passing one quiz set `tier` and `is_verified` for the
-- whole account.
--
-- That cannot express what this flow needs - "expert on Samsung aircon,
-- intermediate on LG washing machines" - so competence moves down to a row per
-- category/device/brand combination.
--
-- ## Two levels of skill, and why both survive
--
--   technicians.tier              standard | pro | elite   - account-wide
--   technician_specializations.skill_level
--                                 beginner | intermediate | expert - per row
--
-- `tier` is left alone because RB-CARS Stage 1 ranks on it and its schema was
-- frozen by the user. It now means "the best level this technician has reached
-- anywhere", derived in section 6 rather than set by hand. `skill_level` is
-- what the matcher should consult once it is taught to, since a technician who
-- is expert on laptops is not thereby expert on refrigerators.

-- ---------------------------------------------------------------------------
-- 1. Specialisations
-- ---------------------------------------------------------------------------
--
-- One row per (device_type, brand) pair. The brief calls for multi-select
-- device types and multi-select brands within each, which is a many-to-many;
-- storing the cross product as rows keeps every downstream query a plain
-- equality filter instead of an array containment test.
--
-- `device_type` and `brand` are `text`, not enums or lookup tables. The brand
-- list must accept "Others" with free text - a technician who services a brand
-- SUGO has never heard of is a technician SUGO wants - and a foreign key to a
-- fixed brand table would make that impossible. The canonical lists live in
-- the Flutter `SpecializationCatalog` so the UI offers consistent choices,
-- while the database stays permissive.

create table if not exists public.technician_specializations (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,
  category text not null check (category in ('it_device', 'appliance')),
  device_type text not null,
  brand text not null,

  -- Null until the assessment for this combination has been passed. Null is
  -- meaningful here: "declared but unproven" is a real state the review screen
  -- has to show, and it is why this column is not defaulted to 'beginner'.
  skill_level text check (skill_level in ('beginner', 'intermediate', 'expert')),

  -- Set only by `record_assessment_result()`. A technician can declare any
  -- specialisation they like; only a passed assessment marks it verified, and
  -- only verified rows should ever reach the matcher.
  verified boolean not null default false,

  created_at timestamptz not null default now()
);

comment on table public.technician_specializations is
  'One row per device type + brand a technician services. skill_level stays '
  'null and verified stays false until the matching assessment is passed.';

-- Declaring the same brand for the same device twice is a duplicate, not a
-- second qualification. Enforced here rather than in the picker so a retry or
-- a double tap cannot create one.
create unique index if not exists uniq_technician_specialization
  on public.technician_specializations (technician_id, device_type, brand);

create index if not exists idx_technician_specializations_technician
  on public.technician_specializations (technician_id);

-- The matcher's lookup: "who is verified for this device and brand?"
create index if not exists idx_technician_specializations_lookup
  on public.technician_specializations (device_type, brand)
  where verified = true;

-- ---------------------------------------------------------------------------
-- 2. Assessment results
-- ---------------------------------------------------------------------------
--
-- Separate from the existing `technician_assessments` table, which stays for
-- the account-wide quiz already in production. This one is per specialisation
-- and records *every* attempt including failures, which the old table could
-- not do - under deferred registration a failed attempt had no technician row
-- to attach to. Now the row exists from sign-up, so failures can be stored,
-- which is what makes a retake cooldown enforceable at all.

create table if not exists public.technician_assessment_results (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,
  specialization_id uuid not null
    references public.technician_specializations(id) on delete cascade,

  score numeric(5,2) not null check (score >= 0 and score <= 100),
  passed boolean not null,
  attempt_number integer not null check (attempt_number > 0),
  taken_at timestamptz not null default now()
);

comment on table public.technician_assessment_results is
  'Every assessment attempt, passed or failed. Failures are retained because '
  'the retake cooldown is computed from the last attempt time.';

create index if not exists idx_assessment_results_technician
  on public.technician_assessment_results (technician_id);

create index if not exists idx_assessment_results_specialization
  on public.technician_assessment_results (specialization_id, taken_at desc);

-- ---------------------------------------------------------------------------
-- 2b. Row level security for both tables above
-- ---------------------------------------------------------------------------
--
-- Enabling RLS is not optional bookkeeping here. A table with RLS switched off
-- is readable and writable by `anon` through the public API using nothing but
-- the key shipped inside the app. For these two that would mean anyone could
-- list every technician on the platform with their brands, and - far worse -
-- insert their own `technician_assessment_results` row with `passed = true`.

alter table public.technician_specializations enable row level security;
alter table public.technician_assessment_results enable row level security;

drop policy if exists "technician_specializations_own" on public.technician_specializations;
create policy "technician_specializations_own"
  on public.technician_specializations for select to authenticated
  using (technician_id = auth.uid());

-- Declaring a specialisation is the technician's own act, so insert is theirs.
-- The WITH CHECK pins the two award columns to their starting values: without
-- it, the picker screen could file a row that arrives already
-- `verified = true, skill_level = 'expert'` and skip the assessment entirely.
drop policy if exists "technician_specializations_insert_own" on public.technician_specializations;
create policy "technician_specializations_insert_own"
  on public.technician_specializations for insert to authenticated
  with check (
    technician_id = auth.uid()
    and verified = false
    and skill_level is null
  );

-- Removing a specialisation is allowed only while it is unproven. Deleting a
-- verified one would discard the assessment history that justified it, and the
-- cascade on `technician_assessment_results` would take the attempt records
-- with it - including the failures a cooldown is computed from.
drop policy if exists "technician_specializations_delete_unverified" on public.technician_specializations;
create policy "technician_specializations_delete_unverified"
  on public.technician_specializations for delete to authenticated
  using (technician_id = auth.uid() and verified = false);

-- No UPDATE policy at all. `skill_level` and `verified` are the only mutable
-- columns and both are awarded by `record_assessment_result()` on the service
-- role. Changing a device type or brand means deleting the row and declaring
-- the correct one, which correctly forces a fresh assessment.

-- Read-only to the technician: they see their scores, they never write them.
drop policy if exists "technician_assessment_results_select_own" on public.technician_assessment_results;
create policy "technician_assessment_results_select_own"
  on public.technician_assessment_results for select to authenticated
  using (technician_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. The grading bands, in one place
-- ---------------------------------------------------------------------------
--
-- 90-100 expert, 70-89 intermediate, below 70 a fail requiring a retake.
--
-- These thresholds are written as a function rather than inlined so the app,
-- the edge function and the admin panel cannot drift apart on where the line
-- sits. Note this is stricter than the existing account-wide quiz, which
-- passes at 60 (`AssessmentResult.passThreshold`): a per-brand claim is a
-- narrower and more specific promise to a client than "can fix appliances",
-- so it is held to a higher bar.
--
-- IMMUTABLE because the output depends on nothing but the input, which lets
-- Postgres use it in an index or a generated column later if needed.

create or replace function public.assessment_skill_level(p_score numeric)
returns text
language sql
immutable
as $function$
  select case
    when p_score >= 90 then 'expert'
    when p_score >= 70 then 'intermediate'
    else null            -- below the pass mark: no level is awarded
  end;
$function$;

comment on function public.assessment_skill_level(numeric) is
  'Score -> skill level. 90+ expert, 70-89 intermediate, below 70 null (fail). '
  'Single source of truth for the grading bands.';

-- How long a failed attempt must wait before retrying.
--
-- 24 hours is a placeholder, and deliberately a named constant rather than a
-- literal scattered through the code. The reasoning behind the number: long
-- enough that the fastest path to passing is to go and learn the material
-- rather than to brute-force the question bank, short enough that a genuine
-- candidate who misread a question is not lost to the platform for a week.
-- Tune it once, here.
create or replace function public.assessment_retake_cooldown()
returns interval
language sql
immutable
as $function$
  select interval '24 hours';
$function$;

-- ---------------------------------------------------------------------------
-- 4. Recording an attempt
-- ---------------------------------------------------------------------------
--
-- Attempt numbering, cooldown enforcement and the skill-level award all happen
-- here, on the server. None of the three can be left to the client: the app
-- could otherwise claim attempt 1 forever, ignore the cooldown by not asking,
-- and award itself `expert` with a hand-written score.
--
-- SECURITY DEFINER, service-role only. The `submit-assessment` edge function
-- marks the paper - it is the only party that can read `correct_choice_index`,
-- revoked from client roles back in 20260906000002 - and then calls this.

create or replace function public.record_assessment_result(
  p_technician_id uuid,
  p_specialization_id uuid,
  p_score numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_last_attempt timestamptz;
  v_last_passed boolean;
  v_attempt integer;
  v_level text;
  v_passed boolean;
  v_cooldown interval := public.assessment_retake_cooldown();
begin
  -- The specialisation must belong to the technician being scored. Without
  -- this check a caller could pass someone else's specialisation id and
  -- qualify their row.
  if not exists (
    select 1 from public.technician_specializations
    where id = p_specialization_id and technician_id = p_technician_id
  ) then
    raise exception 'Specialisation % does not belong to technician %',
      p_specialization_id, p_technician_id;
  end if;

  select taken_at, passed into v_last_attempt, v_last_passed
  from public.technician_assessment_results
  where specialization_id = p_specialization_id
  order by taken_at desc
  limit 1;

  -- Already qualified. Re-sitting a passed assessment could only lower the
  -- recorded level, so it is refused rather than silently ignored.
  if v_last_passed then
    raise exception 'This specialisation has already been passed';
  end if;

  if v_last_attempt is not null and v_last_attempt + v_cooldown > now() then
    raise exception 'Retake available at %', v_last_attempt + v_cooldown
      using errcode = '55000';  -- object_not_in_prerequisite_state
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_attempt
  from public.technician_assessment_results
  where specialization_id = p_specialization_id;

  v_level := public.assessment_skill_level(p_score);
  v_passed := v_level is not null;

  insert into public.technician_assessment_results (
    technician_id, specialization_id, score, passed, attempt_number
  )
  values (p_technician_id, p_specialization_id, p_score, v_passed, v_attempt);

  -- A failure leaves the specialisation exactly as it was: unverified, no
  -- level. It is not deleted - the technician keeps the declaration and can
  -- retry after the cooldown.
  if v_passed then
    update public.technician_specializations
    set skill_level = v_level,
        verified = true
    where id = p_specialization_id;
  end if;

  return jsonb_build_object(
    'passed', v_passed,
    'score', p_score,
    'skill_level', v_level,
    'attempt_number', v_attempt,
    'retake_available_at',
      case when v_passed then null else now() + v_cooldown end
  );
end;
$function$;

revoke all on function public.record_assessment_result(uuid, uuid, numeric)
  from public, anon, authenticated;
grant execute on function public.record_assessment_result(uuid, uuid, numeric)
  to service_role;

-- ---------------------------------------------------------------------------
-- 5. Trust-boosting documents
-- ---------------------------------------------------------------------------
--
-- Unlike the ID + selfie, these are optional. Nothing in the flow blocks on
-- them and an account reaches `active` without a single one; they exist to
-- raise `verification_tier` (section 6), which is a ranking signal rather than
-- a gate.

create table if not exists public.technician_verification_documents (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,
  doc_type text not null
    check (doc_type in ('certificate', 'nbi_clearance', 'portfolio')),
  file_url text not null,

  -- Portfolio images carry an optional caption. Certificates and clearances
  -- ignore it. One nullable column beats a second table for one string.
  caption text,

  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  admin_notes text,
  reviewed_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now(),
  reviewed_at timestamptz
);

comment on table public.technician_verification_documents is
  'Optional trust-boosting uploads: TESDA/vendor certificates, NBI clearance, '
  'portfolio images. Never gates activation - only raises verification_tier.';

create index if not exists idx_verification_documents_technician
  on public.technician_verification_documents (technician_id, doc_type);

create index if not exists idx_verification_documents_pending
  on public.technician_verification_documents (uploaded_at)
  where status = 'pending';

alter table public.technician_verification_documents enable row level security;

drop policy if exists "verification_documents_select_own"
  on public.technician_verification_documents;
create policy "verification_documents_select_own"
  on public.technician_verification_documents for select to authenticated
  using (technician_id = auth.uid());

-- Same shape as the identity insert policy: the caller may only file a
-- `pending` row, never a pre-approved one.
drop policy if exists "verification_documents_insert_own"
  on public.technician_verification_documents;
create policy "verification_documents_insert_own"
  on public.technician_verification_documents for insert to authenticated
  with check (technician_id = auth.uid() and status = 'pending');

-- Deleting an upload is allowed, but only while it is still pending. Once a
-- reviewer has ruled on a document, removing it would erase the audit trail -
-- including a rejection for a forged certificate.
drop policy if exists "verification_documents_delete_pending"
  on public.technician_verification_documents;
create policy "verification_documents_delete_pending"
  on public.technician_verification_documents for delete to authenticated
  using (technician_id = auth.uid() and status = 'pending');

-- ---------------------------------------------------------------------------
-- 6. Technician profile columns
-- ---------------------------------------------------------------------------
--
-- Added to `technicians`, which is the table the brief calls
-- `technician_profiles`. There is no separate profiles table for technicians:
-- `technicians.id` is the same uuid as `profiles.id`, which is what lets every
-- RLS policy compare a column straight against `auth.uid()`. Adding a third
-- table for four columns would break that.

alter table public.technicians
  add column if not exists base_latitude numeric(9,6);

alter table public.technicians
  add column if not exists base_longitude numeric(9,6);

-- numeric(9,6) rather than the double precision used by `technicians.latitude`
-- from the RB-CARS schema. Six decimal places is roughly 0.11 m at the equator,
-- far finer than any consumer GPS fix, and a fixed-point type compares and
-- sums exactly - which matters because these feed a radius calculation.
comment on column public.technicians.base_latitude is
  'Shop or home base the service radius is measured from. Distinct from '
  '`latitude`, which is the technician''s live position while working.';

alter table public.technicians
  add column if not exists service_radius_km numeric(5,2) not null default 10
  check (service_radius_km > 0 and service_radius_km <= 100);

comment on column public.technicians.service_radius_km is
  'How far from base they will travel. Defaults to 10 km, the middle option '
  'in the picker, so a technician who skips the step is still matchable.';

alter table public.technicians
  add column if not exists verification_tier text not null default 'basic'
  check (verification_tier in ('basic', 'verified', 'certified_pro'));

comment on column public.technicians.verification_tier is
  'basic = ID approved. verified = + passed assessment. certified_pro = + an '
  'approved certificate or NBI clearance. A display and ranking signal, '
  'separate from `tier`, which is the account-wide skill grade.';

-- The privilege-escalation guard from 20260905000002 covers `is_verified`,
-- `tier`, `badge`, `rating`, `total_jobs` and `current_workload`. It predates
-- `verification_tier`, which is awarded by SUGO on the strength of documents a
-- reviewer approved - so a technician setting it themselves would be claiming
-- credentials nobody checked. Extended here rather than left to be noticed
-- later.
create or replace function public.guard_technician_self_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null or auth.uid() <> new.id then
    return new;
  end if;

  if new.is_verified is distinct from old.is_verified then
    raise exception 'A technician cannot change their own verification status';
  end if;

  if new.tier is distinct from old.tier then
    raise exception 'A technician cannot change their own tier';
  end if;

  if new.verification_tier is distinct from old.verification_tier then
    raise exception 'A technician cannot change their own verification tier';
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

-- Note: the function that validates and files a finished registration,
-- `submit_registration_for_review()`, lives at the end of
-- 20260907000004_client_registration.sql. It has to check the client tables
-- as well as these, so it is defined once both halves of the schema exist
-- rather than forward-referencing tables this migration cannot see.
