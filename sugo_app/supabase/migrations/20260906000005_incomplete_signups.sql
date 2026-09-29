-- SUGO: don't leave half-finished accounts behind
--
-- Signing up creates an `auth.users` row and, via the trigger, a `profiles`
-- row. Someone who then abandons role selection or the ID step leaves an
-- account that can log in, occupies their email address, and shows up in every
-- user count - but cannot do anything.
--
-- Two mechanisms are added here, and one existing property is deliberately kept.
--
--   1. `profiles.onboarding_completed_at` marks a finished registration.
--   2. Onboarding-owned tables cascade, so a purge is not blocked by a failed
--      quiz attempt.
--   3. Job-related foreign keys are left WITHOUT cascade on purpose - see the
--      note at the bottom. That is the safety net.

-- ---------------------------------------------------------------------------
-- 1. Mark a finished registration
-- ---------------------------------------------------------------------------
--
-- "Finished" differs per role, which is why this is a stored timestamp rather
-- than something recomputed:
--
--   client     - role chosen and an ID submitted
--   technician - role chosen, ID submitted, specialisation set, assessment
--                passed (is_verified = true)
--
-- The app writes it the first time the router sends someone to a dashboard.
-- Null therefore means "never got that far", which is exactly the set that is
-- safe to purge.

alter table public.profiles
  add column if not exists onboarding_completed_at timestamptz;

comment on column public.profiles.onboarding_completed_at is
  'Set when the account first reaches a dashboard. Null means registration '
  'was abandoned partway and the account is eligible for cleanup.';

create index if not exists idx_profiles_incomplete
  on public.profiles (created_at)
  where onboarding_completed_at is null;

-- ---------------------------------------------------------------------------
-- 2. Cascade the onboarding-owned tables
-- ---------------------------------------------------------------------------
--
-- `technician_assessments` and `technician_portfolio` reference
-- `technicians(id)` with no cascade, so a technician who failed the quiz once
-- could never be deleted - the attempt row would block it. Both tables hold
-- data that belongs to the account and has no meaning without it, so they
-- should follow it into the bin.

alter table public.technician_assessments
  drop constraint if exists technician_assessments_technician_id_fkey;

alter table public.technician_assessments
  add constraint technician_assessments_technician_id_fkey
  foreign key (technician_id)
  references public.technicians(id)
  on delete cascade;

alter table public.technician_portfolio
  drop constraint if exists technician_portfolio_technician_id_fkey;

alter table public.technician_portfolio
  add constraint technician_portfolio_technician_id_fkey
  foreign key (technician_id)
  references public.technicians(id)
  on delete cascade;

-- ---------------------------------------------------------------------------
-- 3. Which accounts are safe to remove
-- ---------------------------------------------------------------------------
--
-- A view rather than logic inside the cleanup function, so the rule can be
-- inspected and audited from the SQL editor before anything is deleted.
--
-- Note what is NOT here: any check against `jobs`, `job_matches` or
-- `job_outcomes`. Those foreign keys deliberately have no `on delete cascade`,
-- so Postgres itself refuses to delete an account with real marketplace
-- activity. Relying on the constraint is safer than a WHERE clause we might
-- one day get wrong - the worst case is a delete that fails loudly, rather
-- than one that silently destroys a booking history.

create or replace view public.incomplete_signups as
select
  p.id,
  p.full_name,
  p.role,
  p.created_at,
  p.role_chosen_at,
  p.id_document_url is not null as has_id,
  now() - p.created_at as age
from public.profiles p
where p.onboarding_completed_at is null;

comment on view public.incomplete_signups is
  'Accounts that never finished registration. Candidates for cleanup; the '
  'purge still relies on FK constraints to refuse any account with activity.';

-- The view runs with the caller's permissions, so RLS on `profiles` still
-- applies and an ordinary user sees only themselves. The cleanup function
-- reads it as the service role.
alter view public.incomplete_signups set (security_invoker = on);
