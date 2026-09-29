-- SUGO: let a client take back a request a technician has not answered
--
-- Two things, both serving one journey:
--
--   1. The client's dashboard can now name the technician they are waiting on.
--   2. The client can withdraw that request and choose somebody else.
--
-- ---------------------------------------------------------------------------
-- THE GAP THIS FILLS
-- ---------------------------------------------------------------------------
--
-- `select` puts a job on one technician's dashboard and leaves the other two
-- shortlisted. From that moment the client is waiting, and until now the only
-- thing they could do about it was delete the whole job and post it again -
-- losing the device details, the photos, the location and the ranking that was
-- already computed for them.
--
-- That is a bad trade for the commonest complaint a marketplace gets: *"nobody
-- has answered me."*
--
-- Withdrawing costs none of that. The shortlist is still there - `select`
-- deliberately leaves the other two `shortlisted` rather than retiring them -
-- so putting the chosen row back to `shortlisted` restores exactly the screen
-- the client chose from, with the matching run intact.
--
-- ---------------------------------------------------------------------------
-- WHY AN RPC AND NOT THE EDGE FUNCTION
-- ---------------------------------------------------------------------------
--
-- Every other write to `job_matches` goes through `job-response`, because it
-- needs the service role: the table has SELECT policies only, for either party.
--
-- This one does not need to reach anything the caller cannot already see. It
-- reads their own job, flips one row on it, and touches no secret and no other
-- technician's data. A SECURITY DEFINER function is the smaller tool, it keeps
-- the rule in the same place as the policies it has to agree with, and it
-- deploys with `db push` rather than a separate function deploy.
--
-- The edge function stays the right home for `accept`, `decline`, `reroute`
-- and `complete`, which all write outcome history and adjust technician
-- counters.

-- ---------------------------------------------------------------------------
-- 1. Withdraw
-- ---------------------------------------------------------------------------

create or replace function public.withdraw_technician_offer(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_job     record;
  v_match   record;
begin
  select id, client_id, status
    into v_job
  from public.jobs
  where id = p_job_id;

  if v_job.id is null then
    raise exception 'Job not found' using errcode = 'P0002';
  end if;

  -- Only the client who posted it. A technician cannot withdraw a request
  -- made to them - they have `decline` for that, and it is recorded against
  -- their acceptance rate, which withdrawing deliberately is not.
  if v_job.client_id <> auth.uid() then
    raise exception 'This job belongs to someone else' using errcode = '42501';
  end if;

  -- Past the point of no return. Once a technician has accepted, the job is a
  -- commitment on both sides and cancelling it is a different act with
  -- different consequences - that is `delete_job`, and it is the edge
  -- function's business because it has to unwind counters.
  if v_job.status in ('confirmed', 'in_progress', 'completed', 'cancelled') then
    raise exception 'This job has already been %', v_job.status
      using errcode = '22023';
  end if;

  select id, technician_id
    into v_match
  from public.job_matches
  where job_id = p_job_id and status = 'offered'
  limit 1;

  if v_match.id is null then
    raise exception 'There is no request waiting on this job'
      using errcode = 'P0002';
  end if;

  -- Back to `shortlisted`, not `declined`.
  --
  -- `declined` would mean the technician turned it down, which is false and
  -- would be unfair twice over: it reads as a refusal on their record, and it
  -- removes them from the client's own shortlist. `shortlisted` is the honest
  -- state - ranked, not currently asked - and it is exactly where the row was
  -- before `select` promoted it.
  --
  -- The client may well re-choose the same person; they might simply have
  -- picked the wrong card.
  update public.job_matches
  set status = 'shortlisted'
  where id = v_match.id;

  return jsonb_build_object(
    'job_id', p_job_id,
    'match_id', v_match.id,
    'technician_id', v_match.technician_id,
    'status', 'withdrawn'
  );
end;
$function$;

comment on function public.withdraw_technician_offer(uuid) is
  'Client takes back a request a technician has not answered. Returns the '
  'match to `shortlisted` so the original Top 3 can be chosen from again.';

revoke all on function public.withdraw_technician_offer(uuid) from public;
revoke all on function public.withdraw_technician_offer(uuid) from anon;
grant execute on function public.withdraw_technician_offer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Naming the technician a client is waiting on
-- ---------------------------------------------------------------------------
--
-- The dashboard lists jobs from `jobs`, which carries `assigned_technician_id`
-- and nothing else about the person - and that column stays null until somebody
-- accepts. So a client who had just booked saw a status chip and no name, which
-- is the one fact they actually wanted.
--
-- `profiles` is readable only by its owner, so the name cannot be joined
-- directly. `profile_display()` - added for the chat conversation list in
-- 20260907000013 - already resolves exactly the public subset needed, so this
-- reuses it rather than adding a second definition of "who is this".

create or replace view public.client_job_technicians as
select
  m.job_id,
  m.id                                as match_id,
  m.technician_id,
  m.status                            as match_status,
  m.created_at                        as matched_at,
  public.profile_display(m.technician_id) as technician,
  coalesce(t.tier, 'standard')        as technician_tier,
  coalesce(t.rating, 0)               as technician_rating,
  coalesce(t.is_verified, false)      as technician_verified
from public.job_matches m
join public.jobs j on j.id = m.job_id
left join public.technicians t on t.id = m.technician_id
-- Only the two states that mean "this person is on my job". A shortlisted row
-- is a candidate the client has not chosen, and naming one of three candidates
-- on the dashboard would imply a booking that has not happened.
where m.status in ('offered', 'accepted')
  and j.client_id = auth.uid();

comment on view public.client_job_technicians is
  'The technician a client has requested or had accepted, per job, with the '
  'name resolved. Drives the name and the withdraw action on the dashboard.';

-- `security_invoker` so `job_matches_client_select` decides the rows, not the
-- view owner. The `client_id = auth.uid()` term above is belt and braces.
alter view public.client_job_technicians set (security_invoker = on);

revoke all on table public.client_job_technicians from anon;
grant select on public.client_job_technicians to authenticated;
