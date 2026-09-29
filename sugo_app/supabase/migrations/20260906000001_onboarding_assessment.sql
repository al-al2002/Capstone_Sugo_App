-- SUGO: technician onboarding - ID submission, skills assessment, portfolio
--
-- Adds the tables behind the registration -> role selection -> ID -> quiz ->
-- dashboard flow. `profiles.role` and `technicians.is_available` already exist
-- from 20260905000002, so this migration only adds what is genuinely new.

-- These tables use `gen_random_uuid()` rather than the `uuid_generate_v4()`
-- used by the earlier migrations. It is built into Postgres core (pg_catalog),
-- so it needs no extension and is always on the search path - `db push` runs
-- with a restricted search_path that does not include the `extensions` schema
-- where uuid-ossp lives, which makes the older spelling fail here.

-- ---------------------------------------------------------------------------
-- 1. profiles.role_chosen_at
-- ---------------------------------------------------------------------------
--
-- WHY THIS IS NEEDED. `role` is `not null default 'client'`, so every account
-- already reads as a client the instant it is created. There is no value the
-- column can hold that means "has not decided yet", which means the router
-- could never tell a brand-new signup apart from someone who deliberately
-- picked Client - and the role selection screen would never appear.
--
-- A nullable timestamp is the smallest fix that does not touch the `role`
-- column or its constraint: null means "not asked yet", any value means the
-- person made an explicit choice. It doubles as an audit trail of when.

alter table public.profiles
  add column if not exists role_chosen_at timestamptz;

comment on column public.profiles.role_chosen_at is
  'When the user explicitly picked a role. Null means the role selection '
  'screen has not been completed, since profiles.role defaults to client and '
  'cannot itself express "undecided".';

-- ---------------------------------------------------------------------------
-- 2. ID document columns on technicians
-- ---------------------------------------------------------------------------

alter table public.technicians
  add column if not exists id_document_url text;

alter table public.technicians
  add column if not exists id_submitted_at timestamptz;

comment on column public.technicians.id_document_url is
  'Public URL of the submitted government ID. Format-checked only - see the '
  'TODO in id_upload_screen.dart about real verification.';

-- ---------------------------------------------------------------------------
-- 3. Assessment question bank
-- ---------------------------------------------------------------------------

create table if not exists public.assessment_questions (
  id uuid primary key default gen_random_uuid(),
  specialization text not null,
  question text not null,
  choices jsonb not null,
  correct_choice_index integer not null,
  created_at timestamptz default now()
);

create index if not exists idx_assessment_questions_specialization
  on public.assessment_questions (specialization);

-- ---------------------------------------------------------------------------
-- 4. Assessment attempts
-- ---------------------------------------------------------------------------

create table if not exists public.technician_assessments (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid references public.technicians(id) not null,
  specialization text not null,
  answers jsonb not null,
  score numeric not null,
  total_questions integer not null,
  passed boolean not null,
  suggested_tier text check (suggested_tier in ('standard','pro','elite')),
  created_at timestamptz default now()
);

create index if not exists idx_technician_assessments_technician
  on public.technician_assessments (technician_id);

-- ---------------------------------------------------------------------------
-- 5. Portfolio
-- ---------------------------------------------------------------------------

create table if not exists public.technician_portfolio (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid references public.technicians(id) not null,
  photo_url text,
  description text,
  created_at timestamptz default now()
);

create index if not exists idx_technician_portfolio_technician
  on public.technician_portfolio (technician_id);

-- ---------------------------------------------------------------------------
-- 6. Row level security
-- ---------------------------------------------------------------------------

alter table public.assessment_questions enable row level security;
alter table public.technician_assessments enable row level security;
alter table public.technician_portfolio enable row level security;

drop policy if exists "assessment_questions_read_all" on public.assessment_questions;
create policy "assessment_questions_read_all"
  on public.assessment_questions for select using (true);

drop policy if exists "technician_assessments_own" on public.technician_assessments;
create policy "technician_assessments_own"
  on public.technician_assessments for all using (technician_id = auth.uid());

drop policy if exists "technician_portfolio_own" on public.technician_portfolio;
create policy "technician_portfolio_own"
  on public.technician_portfolio for all using (technician_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 7. Hide the answer key
-- ---------------------------------------------------------------------------
--
-- WHY. `assessment_questions_read_all` is `using (true)`, which is correct -
-- every technician must be able to fetch the questions. But RLS filters *rows*,
-- not *columns*, so that same policy also hands out `correct_choice_index`.
-- Anyone with the anon key could run
--
--   select question, correct_choice_index from assessment_questions;
--
-- and walk into the quiz with the answer key. Since passing auto-sets
-- `is_verified` and the tier, that is a straight path to a fraudulently
-- verified elite technician.
--
-- Column-level privileges are the fix: RLS still allows the row, but the
-- answer column is simply not readable by client roles. The `submit-assessment`
-- edge function reads it through the service role, which these revokes do not
-- affect.

revoke select (correct_choice_index) on public.assessment_questions from anon;
revoke select (correct_choice_index) on public.assessment_questions from authenticated;

-- ---------------------------------------------------------------------------
-- 8. Storage bucket for ID documents
-- ---------------------------------------------------------------------------
--
-- Private, unlike `job-photos`. A government ID must never be world-readable
-- from a URL, so this bucket is not public and is read through signed URLs or
-- the service role only.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'technician-ids',
  'technician-ids',
  false,
  5242880,  -- 5 MB, matching the client-side validation
  array['image/jpeg', 'image/png']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "technician_ids_insert_own" on storage.objects;
create policy "technician_ids_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'technician-ids'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "technician_ids_select_own" on storage.objects;
create policy "technician_ids_select_own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'technician-ids'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "technician_ids_update_own" on storage.objects;
create policy "technician_ids_update_own"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'technician-ids'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Portfolio photos are promotional, so they reuse the public job-photos bucket
-- rather than needing a third bucket.

-- ---------------------------------------------------------------------------
-- 9. Seed: appliance_repair question bank
-- ---------------------------------------------------------------------------
--
-- Ten multiple-choice questions. Inserted only when the specialization has no
-- questions yet, so re-running the migration does not duplicate the bank.

insert into public.assessment_questions
  (specialization, question, choices, correct_choice_index)
select * from (values
  (
    'appliance_repair',
    'A window-type aircon runs but does not cool. Which do you check first?',
    '["Compressor windings","Air filter and evaporator coil for blockage","Remote control batteries","Wall outlet voltage"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'A refrigerator is cold in the freezer but warm in the fridge compartment. Most likely cause?',
    '["Faulty door seal on the freezer","Blocked evaporator fan or defrost failure","Thermostat set too low","Overloaded circuit"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'What does a capacitor do in a single-phase appliance motor?',
    '["Stores refrigerant","Provides the phase shift needed for starting torque","Filters incoming water","Regulates thermostat temperature"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'Before opening any appliance casing, the first safety step is to:',
    '["Wear gloves","Unplug the unit from mains power","Take a photo","Drain the water"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'A washing machine drains but will not spin. Most likely cause?',
    '["Clogged inlet valve","Worn drive belt or faulty lid switch","Wrong detergent","Low water pressure"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'Which instrument measures continuity in a heating element?',
    '["Clamp meter on AC amps","Multimeter set to ohms","Infrared thermometer","Manifold gauge"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'Ice building up on aircon copper piping usually indicates:',
    '["Too much refrigerant","Restricted airflow or low refrigerant charge","A loose electrical terminal","Normal operation in humid weather"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'A microwave runs but does not heat. Which component is the usual suspect?',
    '["Turntable motor","Magnetron or high-voltage diode","Door hinge","Control panel backlight"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'Why must a capacitor be discharged before servicing?',
    '["It may leak refrigerant","It can hold a dangerous charge after unplugging","It resets the timer","It affects the warranty"]'::jsonb,
    1
  ),
  (
    'appliance_repair',
    'An electric fan hums but the blades do not turn. Most likely cause?',
    '["Blown fuse in the plug","Seized bearing or failed start capacitor","Broken speed switch only","Incorrect blade direction"]'::jsonb,
    1
  )
) as seed(specialization, question, choices, correct_choice_index)
where not exists (
  select 1 from public.assessment_questions
  where specialization = 'appliance_repair'
);
