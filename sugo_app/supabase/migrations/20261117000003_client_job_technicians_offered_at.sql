-- SUGO: when the client's request was sent, on the dashboard (2026-11-17)
--
-- An urgent request passes to the next technician five minutes after it was
-- sent (`urgent-offer-sweep`). The client's home card shows that clock, so
-- it needs the moment the request went out: `job_matches.offered_at`.
--
-- Added as the LAST column - `create or replace view` may only append - and
-- nothing else about the view changes: same rows (offered and accepted only,
-- the caller's own jobs), same security_invoker, same grants. A view, not a
-- table: the frozen RB-CARS tables are untouched.

create or replace view public.client_job_technicians
with (security_invoker = on) as
select
  m.job_id,
  m.id                                as match_id,
  m.technician_id,
  m.status                            as match_status,
  m.created_at                        as matched_at,
  public.profile_display(m.technician_id) as technician,
  coalesce(t.tier, 'standard')        as technician_tier,
  coalesce(t.rating, 0)               as technician_rating,
  coalesce(t.is_verified, false)      as technician_verified,
  m.offered_at
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
  'name resolved and when the request was sent (offered_at, for the urgent '
  'five-minute clock). Drives the dashboard card.';

revoke all on table public.client_job_technicians from anon;
grant select on public.client_job_technicians to authenticated;
