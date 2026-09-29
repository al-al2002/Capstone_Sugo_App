-- =============================================================================
-- Technician time off ("On vacation")
-- =============================================================================
--
-- WHAT IT DOES
--
-- A technician can mark days they will not work. While today falls inside one
-- of those periods they are ON VACATION:
--
--   * RB-CARS still matches them. They appear in the Top 3 like anyone else,
--     scored as if their availability switch were off, and the card says
--     "On vacation until <date>". A client whose best local expert is away
--     should see that expert - and see why they cannot have them - rather
--     than be silently shown someone worse.
--   * They cannot be booked. `job-response` refuses the client's `select`
--     while `technician_away_until()` returns a date, which is the only way a
--     match ever becomes an offer on a technician's dashboard.
--
-- WHY A TABLE OF ITS OWN (approved by the user, 2026-09-22)
--
-- `technicians` is one of the four RB-CARS tables, frozen by the user. Time off
-- also has a shape a pair of columns cannot hold: a technician can plan more
-- than one break ahead, and the rows that have passed are a record of when
-- they were away. So it is its own table, keyed to the technician.
--
-- WHY IT IS NOT THE SAME AS THE ONLINE SWITCH
--
-- `technicians.is_available` means "taking jobs right now" and is flipped from
-- the dashboard many times a day; an offline technician can still be booked
-- and simply answers later. Time off is a promise about whole days, planned in
-- advance, and it blocks booking outright. Folding it into the switch would
-- lose both the dates and the difference.
--
-- WHAT A CLIENT CAN SEE
--
-- Only the end date, through `technicians_away()`. The note is for the
-- technician alone ("family trip", "exam week") and is never returned to
-- anyone else; the table itself is readable only by its owner.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. "Today", in the Philippines
-- ---------------------------------------------------------------------------
--
-- Vacations are whole calendar days in the technician's own time zone. The
-- database runs in UTC, where a Manila morning is still "yesterday" until
-- 08:00 - so `current_date` would end a vacation eight hours late and start
-- one eight hours late too. Every rule below asks this function instead.

create or replace function public.manila_today()
returns date
language sql
stable
as $function$
  select (now() at time zone 'Asia/Manila')::date;
$function$;

comment on function public.manila_today() is
  'Today''s date in Asia/Manila. Time off is counted in whole local days.';


-- ---------------------------------------------------------------------------
-- 2. The table
-- ---------------------------------------------------------------------------

create table if not exists public.technician_time_off (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,

  -- Inclusive on both ends: 1-3 October is three days off.
  starts_on date not null,
  ends_on date not null,

  -- Private to the technician. Never returned to a client.
  note text check (note is null or char_length(note) <= 200),

  created_at timestamptz not null default now(),

  constraint technician_time_off_order check (ends_on >= starts_on),

  -- At most 90 days per period. A technician on vacation still takes a Top 3
  -- place they cannot fill; an open-ended one would do that for months. A
  -- longer break is several periods, each a deliberate choice.
  constraint technician_time_off_length check (ends_on - starts_on < 90)
);

create index if not exists technician_time_off_lookup
  on public.technician_time_off (technician_id, ends_on);

comment on table public.technician_time_off is
  'Days a technician will not work. While today is inside a period they are '
  'still matched but cannot be booked. Readable only by the technician.';


-- ---------------------------------------------------------------------------
-- 3. Rules a CHECK constraint cannot express
-- ---------------------------------------------------------------------------
--
-- Both depend on other rows or on today's date, so they live in a trigger:
--
--   * no new period may start in the past - "I was on vacation last week"
--     would rewrite why a booking was or was not possible;
--   * periods may not overlap - "until" must have one answer.
--
-- Shortening a period that has already started (ending a vacation early) is
-- allowed: only a CHANGED start date is re-checked against today.

create or replace function public.technician_time_off_guard()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  -- The owner cannot be moved to someone else's calendar.
  if tg_op = 'UPDATE' and new.technician_id is distinct from old.technician_id then
    raise exception 'Time off cannot be moved to another technician'
      using errcode = '42501';
  end if;

  if (tg_op = 'INSERT' or new.starts_on is distinct from old.starts_on)
     and new.starts_on < public.manila_today() then
    raise exception 'Time off cannot start in the past'
      using errcode = '23514';
  end if;

  if exists (
    select 1 from public.technician_time_off o
    where o.technician_id = new.technician_id
      and o.id <> new.id
      and o.starts_on <= new.ends_on
      and o.ends_on >= new.starts_on
  ) then
    raise exception 'These dates overlap time off you already have'
      using errcode = '23P01';
  end if;

  return new;
end;
$function$;

drop trigger if exists technician_time_off_guard on public.technician_time_off;
create trigger technician_time_off_guard
  before insert or update on public.technician_time_off
  for each row execute function public.technician_time_off_guard();


-- ---------------------------------------------------------------------------
-- 4. Row level security: the technician's own calendar only
-- ---------------------------------------------------------------------------

alter table public.technician_time_off enable row level security;

drop policy if exists "time_off_select_own" on public.technician_time_off;
create policy "time_off_select_own"
  on public.technician_time_off for select to authenticated
  using (technician_id = auth.uid());

-- Inserting requires a technicians row, so a client cannot give themselves
-- a vacation that some later query might misread.
drop policy if exists "time_off_insert_own" on public.technician_time_off;
create policy "time_off_insert_own"
  on public.technician_time_off for insert to authenticated
  with check (
    technician_id = auth.uid()
    and exists (select 1 from public.technicians t where t.id = auth.uid())
  );

drop policy if exists "time_off_update_own" on public.technician_time_off;
create policy "time_off_update_own"
  on public.technician_time_off for update to authenticated
  using (technician_id = auth.uid())
  with check (technician_id = auth.uid());

drop policy if exists "time_off_delete_own" on public.technician_time_off;
create policy "time_off_delete_own"
  on public.technician_time_off for delete to authenticated
  using (technician_id = auth.uid());

revoke all on public.technician_time_off from anon;
grant select, insert, update, delete on public.technician_time_off to authenticated;


-- ---------------------------------------------------------------------------
-- 5. The single definition of "on vacation"
-- ---------------------------------------------------------------------------
--
-- The last day of the period covering today, or null. Every consumer - the
-- matching pool, the booking gate, the listings - asks this one function, so
-- they cannot disagree about who is away.
--
-- SECURITY DEFINER because its callers (the booking gate on the service role,
-- `technicians_away()` for clients) must see rows the select-own policy hides.
-- It returns a date and nothing else - never the note.

create or replace function public.technician_away_until(p_technician_id uuid)
returns date
language sql
stable
security definer
set search_path = public
as $function$
  select o.ends_on
  from public.technician_time_off o
  where o.technician_id = p_technician_id
    and public.manila_today() between o.starts_on and o.ends_on
  limit 1;
$function$;

comment on function public.technician_away_until(uuid) is
  'Last day of the time off covering today (Asia/Manila), or null when the '
  'technician is working. The one definition of "on vacation".';

-- Functions default to EXECUTE for PUBLIC. This one reads a private table,
-- so it is closed first and opened only to the server.
revoke all on function public.technician_away_until(uuid) from public, anon, authenticated;
grant execute on function public.technician_away_until(uuid) to service_role;


-- ---------------------------------------------------------------------------
-- 6. The matching pool learns who is away
-- ---------------------------------------------------------------------------
--
-- Copied from 20260907000010 (not retyped) with one column appended. The
-- engine selects `*`, so it receives `away_until` with no extra query, and
-- Stage 2 scores a technician on vacation exactly as it scores one who is
-- offline - present, labelled, and ranked below anyone who can take the job.

create or replace view public.matching_candidates as
select
  t.id,
  t.skill_tags,
  t.tier,
  t.specialization,
  t.is_verified,
  t.is_available,
  t.badge,
  t.rating,
  t.total_jobs,
  t.current_workload,
  -- Live position while working. May be null and may be stale.
  t.latitude,
  t.longitude,
  -- Where they actually work from, set during registration. This is what the
  -- service radius is measured from.
  t.base_latitude,
  t.base_longitude,
  t.service_radius_km,
  t.verification_tier,
  t.created_at,
  p.full_name,
  p.avatar_url,
  p.phone,
  exists (
    select 1 from public.identity_verifications iv
    where iv.user_id = t.id and iv.status = 'approved'
  ) as identity_approved,
  coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'device_type', s.device_type,
          'brand', s.brand,
          'skill_level', s.skill_level,
          'verified', s.verified,
          'track', s.track
        )
        order by s.created_at
      )
      from public.technician_specializations s
      where s.technician_id = t.id
    ),
    '[]'::jsonb
  ) as specializations,
  -- NEW (20260922000003). The last day of the time off covering today, or
  -- null when they are working. Appended last: `create or replace view` may
  -- only add columns at the end, and every earlier column is unchanged.
  public.technician_away_until(t.id) as away_until
from public.technicians t
join public.profiles p on p.id = t.id;

comment on view public.matching_candidates is
  'The RB-CARS candidate pool with identity status, base location, service '
  'radius, verification tier, declared specialisations and time off already '
  'joined. Read by match-technician on the service role.';

-- `create or replace view` keeps grants; restated so this file says it too.
revoke all on public.matching_candidates from anon, authenticated;
grant select on public.matching_candidates to service_role;


-- ---------------------------------------------------------------------------
-- 7. What a client may know: who is away, and until when
-- ---------------------------------------------------------------------------
--
-- The listings (Recommended, the job's wider list, a profile) ask this with
-- the ids they are about to show and badge the ones it returns. It is a
-- separate call rather than a new column on `technician_card` so the ranking
-- functions behind those listings - tuned and verified already - are not
-- rewritten for a label.
--
-- Returns only technicians who are away today, and only the end date. Capped
-- at 100 ids: no screen shows more, and the cap stops it being used to sweep
-- the whole table in one request.

create or replace function public.technicians_away(p_ids uuid[])
returns table (technician_id uuid, away_until date)
language plpgsql
stable
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  if coalesce(cardinality(p_ids), 0) > 100 then
    raise exception 'Ask about at most 100 technicians at a time'
      using errcode = '22023';
  end if;

  return query
    select t.id, public.technician_away_until(t.id)
    from public.technicians t
    where t.id = any(p_ids)
      and t.is_verified
      and public.technician_away_until(t.id) is not null;
end;
$function$;

comment on function public.technicians_away(uuid[]) is
  'For up to 100 technician ids, the ones on vacation today and the last day '
  'of it. The only view of time off a client gets - never the note.';

revoke all on function public.technicians_away(uuid[]) from public, anon;
grant execute on function public.technicians_away(uuid[]) to authenticated;
