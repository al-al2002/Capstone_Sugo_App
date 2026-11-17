-- SUGO: the assigned technician can see their client's phone (2026-11-17)
--
-- On a job the technician has taken, they need to reach the client - to say
-- they are running late, to find the house, to agree a time to collect a
-- unit. The client already gets the technician's phone once they have a
-- booking (`technician_profile`, 20260916000008). This is the same release
-- in the other direction.
--
-- ## Who gets it, and when
--
-- Only the technician ASSIGNED to the job, and only while it is confirmed
-- or in progress - the window in which they actually have to reach the
-- client. Nobody browsing, an offered-only technician who has not accepted,
-- or a technician on a finished job gets anything: the function returns
-- null for all of them. `client_profile` (the public view of a client) still
-- withholds the phone, as it should.
--
-- ## Why a function, not a policy
--
-- `profiles` is readable by its owner only. Opening a policy on it would
-- expose the whole row; a SECURITY DEFINER function returns one column, for
-- one job, after checking the caller - the same pattern as the technician
-- listings. No table, column or policy changes.

create or replace function public.job_client_phone(p_job_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $function$
  select nullif(trim(p.phone), '')
  from public.jobs j
  join public.profiles p on p.id = j.client_id
  where j.id = p_job_id
    and j.assigned_technician_id = auth.uid()
    and j.status in ('confirmed', 'in_progress');
$function$;

comment on function public.job_client_phone(uuid) is
  'The client''s phone, for the technician assigned to that job while it is '
  'confirmed or in progress. Null for anyone else.';

revoke all on function public.job_client_phone(uuid) from public, anon;
grant execute on function public.job_client_phone(uuid) to authenticated;
