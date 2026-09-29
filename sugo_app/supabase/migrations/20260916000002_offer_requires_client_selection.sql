-- SUGO: a job reaches a technician only after the client picks them
--
-- ## The bug
--
-- `match-technician` wrote all three Top 3 rows into `job_matches` with
-- `status = 'offered'` the moment a job was posted. The technician dashboard
-- reads exactly that - `job_matches` where `technician_id = me` and
-- `status = 'offered'` - so ALL THREE technicians saw the job as an incoming
-- request before the client had chosen anybody.
--
-- From the technician's side that looks like "every task shows up on my
-- dashboard even though nobody booked me", which is what it was.
--
-- ## Why the old design did that
--
-- `job_matches.status` had only three values - offered, declined, accepted -
-- so there was no way to say "this technician is on the client's shortlist but
-- has not been asked yet". `offered` was doing two jobs at once: "the engine
-- ranked you" and "a client wants you". The dashboard could only read the
-- second meaning, so it read the first one by mistake.
--
-- ## The fix
--
-- A fourth status, `shortlisted`, splits those two meanings apart:
--
--   shortlisted  the engine ranked you into the Top 3. Visible to the CLIENT,
--                who is choosing. NOT visible to the technician.
--   offered      the client picked you. Now it is on your dashboard, and you
--                can accept, reroute or decline.
--   accepted     you took it.
--   declined     you turned it down, or the client picked somebody else.
--
-- `offered` now means what the technician dashboard always assumed it meant, so
-- the dashboard query does not change at all - the bug was that rows arrived in
-- that state too early, not that the query was wrong.
--
-- ## Scope note
--
-- This widens a CHECK constraint on `job_matches`, one of the four frozen
-- RB-CARS tables. No table is added, no column is added, and no policy is
-- loosened - the one policy touched below is made STRICTER. Flagging it because
-- the four-table schema is deliberately frozen and this is a change to it.

-- ---------------------------------------------------------------------------
-- 1. The new status
-- ---------------------------------------------------------------------------

alter table public.job_matches
  drop constraint if exists job_matches_status_check;

alter table public.job_matches
  add constraint job_matches_status_check
  check (status in ('shortlisted', 'offered', 'declined', 'accepted'));

-- The default moves with the meaning. A row inserted without an explicit status
-- is one the engine produced, and an engine result is a shortlist entry, not a
-- booking. Defaulting to `offered` is what made the old bug a one-word mistake
-- away at all times.
alter table public.job_matches
  alter column status set default 'shortlisted';

comment on column public.job_matches.status is
  'shortlisted = ranked by the engine, visible to the client only. '
  'offered = the client chose this technician and it is on their dashboard. '
  'accepted / declined = the technician answered, or the client chose someone '
  'else. Only `offered` rows may be accepted, rerouted or declined.';

-- ---------------------------------------------------------------------------
-- 2. Existing rows
-- ---------------------------------------------------------------------------
--
-- The past jobs the technicians can currently see have to be corrected too,
-- otherwise the fix only applies to jobs posted from now on.
--
-- HOW A SELECTED ROW IS TOLD APART FROM AN UNSELECTED ONE. When a client
-- selected someone, `handleClientSelect` set the other two rows to `declined`.
-- So a job left with MORE THAN ONE `offered` row is definitively one where the
-- client never chose - every one of those rows is a shortlist entry that leaked
-- onto a dashboard, and all of them become `shortlisted`.
--
-- A job with exactly ONE `offered` row is left alone. It is either a real
-- client selection or a match that only ever found one candidate, and those two
-- cannot be told apart from the data. Leaving them is the conservative choice:
-- it may leave one technician seeing one old task they were not explicitly
-- booked for, but it cannot cancel a booking that a client genuinely made and
-- is waiting on.

with unselected as (
  select job_id
  from public.job_matches
  where status = 'offered'
  group by job_id
  having count(*) > 1
)
update public.job_matches m
set status = 'shortlisted'
from unselected u
where m.job_id = u.job_id
  and m.status = 'offered';

-- ---------------------------------------------------------------------------
-- 3. The database enforces it too, not just the query
-- ---------------------------------------------------------------------------
--
-- The dashboard filters on `status = 'offered'`, but a filter in Dart is a
-- display choice, not a boundary: `job_matches_technician_select` as written
-- let a technician read every row addressed to them, shortlist included, with
-- nothing but the app's own WHERE clause standing in the way.
--
-- Adding the status test makes the leak impossible rather than merely unused.
-- This STRICTLY REDUCES what a technician can read; no policy is widened.
--
-- The client's policy is deliberately untouched: `job_matches_client_select`
-- must keep showing all four statuses, because the shortlist is exactly what
-- the client is choosing from.

drop policy if exists "job_matches_technician_select" on public.job_matches;
create policy "job_matches_technician_select"
  on public.job_matches for select
  using (technician_id = auth.uid() and status <> 'shortlisted');

-- Serves the dashboard's "my offers" read and the engine's shortlist sweep.
create index if not exists idx_job_matches_technician_status
  on public.job_matches (technician_id, status);
