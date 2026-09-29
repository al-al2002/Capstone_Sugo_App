-- SUGO: let a technician create their own row
--
-- ## The bug this fixes
--
-- Role selection failed with "Could not save your choice" whenever someone
-- tapped **Continue as Technician**. Choosing Client worked fine.
--
-- The cause: the RB-CARS migration gave `technicians` a SELECT policy and an
-- UPDATE policy, and no INSERT policy at all.
--
--   create policy "technicians_select_own" ... for select using (id = auth.uid());
--   create policy "technicians_update_own" ... for update using (id = auth.uid());
--
-- With RLS enabled, an operation with no matching policy is denied. Nothing had
-- ever inserted into the table before - the seed script runs as the service
-- role, which bypasses RLS - so the gap went unnoticed until the onboarding
-- flow needed to create a row from a normal user session.
--
-- ## Why the WITH CHECK is not just `id = auth.uid()`
--
-- The guard trigger added in 20260905000002 stops a technician *updating* their
-- own `is_verified`, `tier`, `rating`, `total_jobs` and `current_workload`. It
-- is a BEFORE UPDATE trigger, so it never fires on an INSERT.
--
-- That means a naive insert policy would reopen the exact hole the trigger was
-- written to close, just one step earlier: a technician could create their row
-- already verified at elite tier with a 5.0 rating, skip the assessment
-- entirely, and go straight into the matching pool.
--
-- So the policy pins every privileged column to its starting value at creation
-- time. A technician may bring themselves into existence, but only as an
-- unverified standard-tier newcomer with no history. Everything after that is
-- the trigger's job.

drop policy if exists "technicians_insert_own" on public.technicians;
create policy "technicians_insert_own"
  on public.technicians for insert to authenticated
  with check (
    id = auth.uid()
    -- Verification is earned through the assessment, never self-granted.
    and is_verified = false
    -- Tier is awarded by the assessment score.
    and tier = 'standard'
    -- Reputation and workload are computed from real jobs, so a new row must
    -- start empty. coalesce() because these columns are nullable with defaults.
    and coalesce(rating, 0) = 0
    and coalesce(total_jobs, 0) = 0
    and coalesce(current_workload, 0) = 0
  );

comment on policy "technicians_insert_own" on public.technicians is
  'A user may create their own technician row, but only in the unverified '
  'standard-tier starting state. Complements guard_technician_self_update, '
  'which covers the UPDATE path.';
