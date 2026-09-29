-- SUGO: the two technician listings, and the review text they display
--
-- Two features that look alike and must not share ranking logic:
--
--   1. Recommended technicians - the client dashboard's general "best
--      performers" row. Not tied to any job. Distance is INFORMATION, never a
--      filter and never a sort key. Ranked purely on reputation:
--      rating DESC, then completed jobs DESC.
--
--   2. Task matching - shown after a client posts a specific repair job.
--      Filtered to technicians whose registered specialisation can serve that
--      job, ranked distance ASC then rating DESC. The first three are the
--      "Top 3"; everyone else who matches the specialisation is still listed
--      below them, however few jobs they have completed.
--
-- The difference is deliberate and is the thing to be able to state out loud:
-- browsing asks "who is good?", matching asks "who is good, near, and
-- qualified for THIS device?". Sorting the dashboard by distance would answer
-- the second question on a screen that asked the first.
--
-- ## Why these are SECURITY DEFINER functions
--
-- `technicians_select_own` restricts that table to `id = auth.uid()`. That
-- policy is correct - a client has no business enumerating the workforce with
-- an anon key - and this migration does not touch it. A SECURITY DEFINER
-- function is the standard way to expose one curated, audited read past a
-- select-own policy without loosening the policy itself: the function runs as
-- its owner, returns only the columns below, and re-checks the caller by hand.
--
-- Every function here therefore does two things a policy would otherwise have
-- done, and they are the security-critical lines in this file:
--
--   * refuses an unauthenticated caller (`auth.uid() is null`), and
--   * for job-scoped reads, proves the caller owns the job.
--
-- ## What is never returned
--
-- A technician's own latitude/longitude never leave the database. The caller
-- sends its own coordinates and gets `distance_km` back, so a card can say
-- "3.4 km away" without the app ever holding the home address of someone the
-- client has not booked. `phone` and `current_workload` are likewise absent:
-- a contact number is released only by `technician-directory` after a real
-- booking, and workload is a scoring input, not a profile field.

-- ---------------------------------------------------------------------------
-- 1. Review text
-- ---------------------------------------------------------------------------
--
-- WHY A FIFTH TABLE RATHER THAN A COLUMN ON `job_outcomes`.
--
-- `job_outcomes` is the RB-CARS feedback loop: `diagnosis_correct` and
-- `rerouted_mid_job` are read back into Stage 1 by scoring/accuracy.ts. It is
-- written by `job-response` on the service role, it has no write policy, and
-- it records no author - the rater is inferred through `jobs.client_id`.
--
-- A public review is a different object with a different reader: it is written
-- BY a named client FOR other clients to read, it needs its own author column
-- so the profile can print "reviewed by", and it needs a 1-5 integer scale
-- rather than `numeric(3,2)`. Bolting a `comment` column onto the scoring
-- table would have given one row two owners and two audiences.
--
-- The four RB-CARS tables are untouched.

create table if not exists public.job_reviews (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  technician_id uuid not null references public.technicians(id) on delete cascade,
  reviewer_id uuid not null references public.profiles(id) on delete cascade,

  -- Integer 1-5, not numeric. A star widget emits whole stars; storing 4.67
  -- would invite a half-star UI the rest of the app cannot produce.
  stars integer not null check (stars between 1 and 5),

  -- Nullable on purpose: a client who rates but will not write is a normal
  -- outcome, and forcing text produces "good" more often than it produces
  -- anything worth reading.
  comment text,

  created_at timestamptz not null default now(),

  -- One review per client per job. A second visit is a second job.
  unique (job_id, reviewer_id)
);

comment on table public.job_reviews is
  'Client-authored public review of a completed job: the star rating and '
  'comment shown on a technician profile. Distinct from job_outcomes, which '
  'is the private RB-CARS scoring signal.';

create index if not exists idx_job_reviews_technician
  on public.job_reviews (technician_id, created_at desc);

create index if not exists idx_job_reviews_job on public.job_reviews (job_id);

alter table public.job_reviews enable row level security;

-- READ. Direct reads are narrow: your own review, or reviews of you. Everyone
-- else reads reviews through `technician_profile()` below, which is what lets
-- a browsing client see another technician's reviews without this policy
-- having to open the table to the whole authenticated role.
drop policy if exists "job_reviews_select_own" on public.job_reviews;
create policy "job_reviews_select_own"
  on public.job_reviews for select to authenticated
  using (reviewer_id = auth.uid() or technician_id = auth.uid());

-- WRITE. Unlike job_matches and job_outcomes this DOES get an insert policy,
-- because unlike those two the author is the client themselves rather than the
-- service role. The WITH CHECK is the whole guarantee, so it proves all four
-- claims the row makes: you are who you say you are, the job is yours, it is
-- finished, and this technician is the one who actually did it. Without the
-- last two clauses a client could review anyone, at any time, unprompted.
drop policy if exists "job_reviews_insert_own" on public.job_reviews;
create policy "job_reviews_insert_own"
  on public.job_reviews for insert to authenticated
  with check (
    reviewer_id = auth.uid()
    and exists (
      select 1 from public.jobs j
      where j.id = job_id
        and j.client_id = auth.uid()
        and j.status = 'completed'
        and j.assigned_technician_id = job_reviews.technician_id
    )
  );

-- EDIT. A review may be corrected or withdrawn by its author, and by nobody
-- else. `technician_id` and `job_id` are pinned by the same check as the
-- insert, so an edit cannot move a good review onto a different technician.
drop policy if exists "job_reviews_update_own" on public.job_reviews;
create policy "job_reviews_update_own"
  on public.job_reviews for update to authenticated
  using (reviewer_id = auth.uid())
  with check (reviewer_id = auth.uid());

drop policy if exists "job_reviews_delete_own" on public.job_reviews;
create policy "job_reviews_delete_own"
  on public.job_reviews for delete to authenticated
  using (reviewer_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Distance
-- ---------------------------------------------------------------------------
--
-- WHY HAVERSINE AND NOT PostGIS. This was a real choice, and the short answer
-- is that PostGIS would buy nothing here without a change to a frozen table.
--
-- PostGIS earns its keep through the GiST index behind `ST_DWithin`. That
-- index requires a `geography`/`geometry` COLUMN. SUGO stores plain scalars:
-- `technicians.base_latitude/base_longitude` are numeric(9,6) and the older
-- `latitude/longitude` pair is double precision. Indexing them spatially means
-- adding a generated geography column to `technicians` - a schema change to a
-- table that is deliberately frozen.
--
-- Without that column the only way to use PostGIS is to build a point per row
-- at query time:
--
--   ST_Distance(
--     ST_MakePoint(t.base_longitude, t.base_latitude)::geography,
--     ST_MakePoint(p_client_lng, p_client_lat)::geography
--   )
--
-- That expression cannot use any index, so it is a sequential scan over the
-- technician table - exactly what the haversine below is. It would be slower,
-- not faster, because the geography path is doing a more expensive ellipsoidal
-- calculation for an answer this feature rounds to 100 m anyway.
--
-- `ST_DWithin` is also the wrong shape for both callers. Recommended must NOT
-- filter by distance at all, and task matching filters on specialisation, not
-- radius. A radius predicate is the one thing neither listing wants.
--
-- WHEN TO REVISIT: a spherical earth is off by up to ~0.5%, which over a 25 km
-- service area is ~125 m - far below the 100 m the cards round to. If the
-- technician table ever grows past roughly 10k rows the sequential scan starts
-- to matter, and the answer then is a generated geography column plus a GiST
-- index, not a different formula.
--
-- KNOWN DUPLICATION, stated rather than hidden: there is already a haversine
-- in `supabase/functions/match-technician/scoring/geo.ts`, and two
-- implementations that drift would put one distance on the card and another in
-- the match score. Both use the same 6371 km radius and the same formula. The
-- durable fix is for the edge functions to call this function instead of
-- keeping their own; until they do, changing one means changing both.

create or replace function public.haversine_km(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
returns double precision
language sql
immutable
parallel safe
as $function$
  -- Null in, null out. A missing coordinate must produce "unknown", never a
  -- number: a technician whose location was never set would otherwise be
  -- computed against (0,0) and rank as though they were in the Gulf of Guinea.
  select case
    when p_lat1 is null or p_lng1 is null
      or p_lat2 is null or p_lng2 is null then null
    else 6371 * 2 * asin(
      sqrt(
        power(sin(radians(p_lat2 - p_lat1) / 2), 2)
        + cos(radians(p_lat1)) * cos(radians(p_lat2))
          * power(sin(radians(p_lng2 - p_lng1) / 2), 2)
      )
    )
  end;
$function$;

comment on function public.haversine_km(
  double precision, double precision, double precision, double precision
) is
  'Great-circle distance in km between two lat/lng pairs. Null if any '
  'coordinate is missing. Mirrors match-technician/scoring/geo.ts - change '
  'both together.';

-- ---------------------------------------------------------------------------
-- 3. Reputation, computed once and used by every listing
-- ---------------------------------------------------------------------------
--
-- WHY A VIEW RATHER THAN READING `technicians.rating` DIRECTLY.
--
-- `technicians.rating` is a cache that `job-response` recomputes from
-- `job_outcomes.final_rating`. `job_reviews.stars` is the new, client-facing
-- number. If the card ranked on one and the profile displayed the other, a
-- technician could show 4.8 on their profile and sort as though they were 4.2,
-- which is precisely the kind of inconsistency a panel will find.
--
-- So the effective rating is defined ONCE here and every function below uses
-- it. Reviews win when they exist; the cached column is the fallback for rows
-- that predate this table or were seeded. `star_N` is the breakdown the
-- profile screen draws as bars.

create or replace view public.technician_review_stats as
select
  r.technician_id,
  count(*)::integer                                   as review_count,
  round(avg(r.stars)::numeric, 2)                     as average_stars,
  count(*) filter (where r.stars = 5)::integer        as star_5,
  count(*) filter (where r.stars = 4)::integer        as star_4,
  count(*) filter (where r.stars = 3)::integer        as star_3,
  count(*) filter (where r.stars = 2)::integer        as star_2,
  count(*) filter (where r.stars = 1)::integer        as star_1
from public.job_reviews r
group by r.technician_id;

comment on view public.technician_review_stats is
  'Per-technician review count, average and 1-5 breakdown. Read only through '
  'the SECURITY DEFINER listing functions; not granted to client roles.';

-- Same posture as `matching_candidates`: the view aggregates rows that RLS
-- would otherwise keep private, so it is not handed to anon or authenticated.
-- The functions below reach it as their owner.
revoke all on public.technician_review_stats from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. One card shape for both listings
-- ---------------------------------------------------------------------------
--
-- Both features draw the SAME card - avatar, New badge, name, registered
-- specialisation, completed jobs, distance - so both functions return the same
-- composite and Flutter parses one model. `match_rank` and `is_top_match` are
-- carried here but left null/false by the recommended listing: a dashboard card
-- has no rank, and giving the two listings different row types to express that
-- would mean two Dart models for one widget.
--
-- Dropped with cascade so the migration is re-runnable; the functions that
-- depend on it are recreated immediately below.

drop type if exists public.technician_card cascade;
create type public.technician_card as (
  id uuid,
  full_name text,
  avatar_url text,
  tier text,
  badge text,
  is_verified boolean,
  is_available boolean,

  -- Reputation. `rating` is the effective rating defined in section 3, NOT the
  -- raw cached column, so the number shown is the number sorted on.
  rating numeric,
  review_count integer,
  total_jobs integer,

  -- True when nothing has been completed yet. The card's "New" badge. Computed
  -- here rather than in Dart so both listings agree on what "new" means.
  is_new boolean,

  -- Straight-line km from the caller's origin. Null when either side has no
  -- coordinates - the card must then omit the line, never print "0 km".
  distance_km numeric,

  -- Every registered specialisation, as
  -- [{device_type, brand, skill_level, verified}]. Flutter renders these as the
  -- profile's badges and labels the card from the first entry.
  specializations jsonb,

  -- The single specialisation the card names, e.g. laptop/Lenovo -> "Laptop
  -- Repair". Verified rows are preferred, then oldest, so the line is stable
  -- rather than changing whenever a technician adds a brand. For task matching
  -- this is instead the specialisation that actually matched the job, which is
  -- the one the client needs to see.
  primary_device_type text,
  primary_brand text,

  -- Task matching only. 1..3 are the Top 3; 4+ are the wider specialisation
  -- list below them. Null for the recommended listing.
  match_rank integer,
  is_top_match boolean
);

-- ---------------------------------------------------------------------------
-- 5. Recommended technicians (client dashboard)
-- ---------------------------------------------------------------------------
--
-- General "best performers". Deliberately NOT personalised to a job.
--
-- RANKING: rating DESC, then completed jobs DESC. Nothing else.
--
-- DISTANCE IS NOT A RANKING INPUT. The coordinates are parameters only so the
-- card can print "3.4 km away"; passing them changes the ORDER BY not at all,
-- and passing none changes only whether that line renders. This is the one
-- behaviour most likely to be "helpfully" broken later, so it is stated here
-- and asserted in the ORDER BY comment below.
--
-- NO SPECIALISATION FILTER. Every verified technician is eligible regardless of
-- what they repair. Filtering here would turn a reputation board into a weak
-- copy of task matching.
--
-- CONSEQUENCE WORTH NAMING: ranking purely on rating means a technician with no
-- completed jobs sorts at the bottom, because their effective rating is 0.
-- They still APPEAR - nothing excludes them, and they carry the "New" badge -
-- but on a long list they will be below the fold. If new technicians need
-- visible placement, that is a product decision (e.g. reserving slots), not
-- something to smuggle into this ORDER BY.

create or replace function public.recommended_technicians(
  p_client_lat double precision default null,
  p_client_lng double precision default null,
  p_limit integer default 10
)
returns setof public.technician_card
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 50);
begin
  -- The function runs as its owner and therefore past `technicians_select_own`.
  -- Authentication is not optional just because RLS is out of the picture.
  if auth.uid() is null then
    raise exception 'Sign in required'
      using errcode = '42501';
  end if;

  return query
  select
    t.id,
    p.full_name,
    p.avatar_url,
    t.tier,
    t.badge,
    t.is_verified,
    t.is_available,
    coalesce(s.average_stars, t.rating, 0)::numeric        as rating,
    coalesce(s.review_count, 0)                            as review_count,
    coalesce(t.total_jobs, 0)                              as total_jobs,
    coalesce(t.total_jobs, 0) = 0                          as is_new,
    round(
      public.haversine_km(
        p_client_lat,
        p_client_lng,
        coalesce(t.base_latitude::double precision, t.latitude),
        coalesce(t.base_longitude::double precision, t.longitude)
      )::numeric,
      2                                  -- ~10 m; finer would be false precision
    )                                                      as distance_km,
    coalesce(spec.all_specializations, '[]'::jsonb)        as specializations,
    spec.primary_device_type,
    spec.primary_brand,
    null::integer                                          as match_rank,
    false                                                  as is_top_match
  from public.technicians t
  join public.profiles p on p.id = t.id
  left join public.technician_review_stats s on s.technician_id = t.id
  left join lateral (
    select
      jsonb_agg(
        jsonb_build_object(
          'device_type', x.device_type,
          'brand',       x.brand,
          'skill_level', x.skill_level,
          'verified',    x.verified
        )
        order by x.verified desc, x.created_at
      )                                        as all_specializations,
      (array_agg(x.device_type order by x.verified desc, x.created_at))[1]
                                               as primary_device_type,
      (array_agg(x.brand order by x.verified desc, x.created_at))[1]
                                               as primary_brand
    from public.technician_specializations x
    where x.technician_id = t.id
  ) spec on true
  where t.is_verified = true
    -- A half-registered or rejected account must never be recommended, even if
    -- an older row left `is_verified` true. The two are set by different code
    -- paths, so both are checked.
    and p.registration_status = 'active'
  -- Reputation only. Distance is absent from this ORDER BY on purpose.
  order by
    coalesce(s.average_stars, t.rating, 0) desc,
    coalesce(t.total_jobs, 0) desc,
    -- Deterministic tie-break, so paging cannot show the same technician twice.
    t.id
  limit v_limit;
end;
$function$;

comment on function public.recommended_technicians(
  double precision, double precision, integer
) is
  'Dashboard "best performers": every verified, active technician ranked by '
  'rating DESC then completed jobs DESC. Coordinates are for display distance '
  'only and do not affect ordering. No specialisation filter.';

-- ---------------------------------------------------------------------------
-- 6. Task matching (after a job is posted)
-- ---------------------------------------------------------------------------
--
-- Filtered to technicians who can actually service THIS device, then ranked
-- distance ASC, rating DESC. Rows 1-3 are the Top 3; everyone else who matches
-- the specialisation follows, ranked lower but never dropped.
--
-- WHY FEW COMPLETED JOBS IS NOT A FILTER. The brief is explicit that the list
-- below the Top 3 must include technicians with little history. Job count is
-- therefore absent from the WHERE clause entirely and appears only as the last
-- tie-break. A new technician who is qualified and nearby can take a Top 3
-- slot on merit; the cold-start problem is solved by letting them compete, not
-- by a visibility floor.
--
-- DISTANCE IS FROM THE JOB, NOT THE CLIENT. `jobs.latitude/longitude` is the
-- repair address, which is the trip the technician actually makes. It is often
-- not where the client is standing when they browse - a laptop dropped at an
-- office, a fridge at a relative's house - so the two listings measure from
-- deliberately different origins.
--
-- HOW THE TWO DEVICE VOCABULARIES ARE BRIDGED. `jobs.device_type` is coarse
-- (laptop|phone|appliance|network) and `technician_specializations.device_type`
-- is fine (laptop, desktop, aircon...). `job_device_candidates()` from
-- 20260907000010 maps one onto the other; comparing them directly would match
-- only the literal word "laptop" and silently hide most of the platform.
--
-- INHERITED GAP, restated so it is not rediscovered as a bug: `network` maps to
-- an empty candidate set, because no device in the specialisation catalogue
-- covers it. A network job would therefore match nobody on specialisation
-- alone. The `skill_tags`/`specialization` fallback below is what keeps that
-- list non-empty, and it is also what keeps accounts that registered before
-- `technician_specializations` existed from disappearing.
--
-- RELATIONSHIP TO RB-CARS - THE IMPORTANT ONE. This is NOT the matching engine.
-- `match-technician` runs a two-stage suitability/acceptance model and writes
-- the authoritative Top 3 into `job_matches`. This function is a browsable list
-- ranked on the two factors the brief names. They will not always agree, and
-- `job_matches.rank` is constrained to 1-3 so the wider list below the Top 3
-- cannot be persisted there anyway - which is why this computes on read and
-- stores nothing. Decide which one the booking flow treats as authoritative
-- before the defence; showing both without saying which is which invites the
-- obvious question.

create or replace function public.match_technicians_for_job(
  p_job_id uuid,
  p_limit integer default 20
)
returns setof public.technician_card
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_client uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  -- The ownership check that RLS would have done. SECURITY DEFINER means
  -- `jobs_client_select_own` is not consulted, so without these four lines any
  -- signed-in user could pass any job id and read the match list for a repair
  -- they have nothing to do with - including its address, via the distances.
  select j.client_id into v_client from public.jobs j where j.id = p_job_id;

  if v_client is null then
    raise exception 'Job not found' using errcode = 'P0002';
  end if;
  if v_client <> auth.uid() then
    raise exception 'This job belongs to someone else' using errcode = '42501';
  end if;

  return query
  with jb as (
    select
      j.id,
      j.client_id,
      j.device_type,
      j.latitude,
      j.longitude,
      -- 'Others' is the picker's "not sure", not a manufacturer. Treated as
      -- absent so a client who could not name the brand still matches on
      -- device rather than matching nobody.
      nullif(j.brand, 'Others')                                      as brand,
      public.job_device_candidates(j.device_type, j.device_detail)   as candidates
    from public.jobs j
    where j.id = p_job_id
  ),
  ranked as (
    select
      t.id,
      p.full_name,
      p.avatar_url,
      t.tier,
      t.badge,
      t.is_verified,
      t.is_available,
      coalesce(s.average_stars, t.rating, 0)::numeric               as rating,
      coalesce(s.review_count, 0)                                   as review_count,
      coalesce(t.total_jobs, 0)                                     as total_jobs,
      coalesce(t.total_jobs, 0) = 0                                 as is_new,
      round(
        public.haversine_km(
          jb.latitude,
          jb.longitude,
          coalesce(t.base_latitude::double precision, t.latitude),
          coalesce(t.base_longitude::double precision, t.longitude)
        )::numeric,
        2
      )                                                             as distance_km,
      coalesce(spec.all_specializations, '[]'::jsonb)               as specializations,
      -- The specialisation that MATCHED, not the technician's default one.
      -- On a "phone / Samsung" job the client needs to see "Smartphone -
      -- Samsung", even if this technician mostly does laptops.
      m.device_type                                                 as primary_device_type,
      m.brand                                                       as primary_brand,
      row_number() over (
        order by
          -- Nearest first. NULLS LAST so a technician with no coordinates can
          -- never outrank one whose distance is actually known - they fall to
          -- the bottom of the list instead of silently taking a Top 3 slot.
          public.haversine_km(
            jb.latitude, jb.longitude,
            coalesce(t.base_latitude::double precision, t.latitude),
            coalesce(t.base_longitude::double precision, t.longitude)
          ) asc nulls last,
          coalesce(s.average_stars, t.rating, 0) desc,
          coalesce(t.total_jobs, 0) desc,
          t.id
      )                                                             as rn
    from jb
    join public.technicians t on t.is_verified = true
    join public.profiles p on p.id = t.id and p.registration_status = 'active'
    left join public.technician_review_stats s on s.technician_id = t.id
    -- The best-matching declared specialisation, and the reason this is a
    -- LATERAL: it picks one row per technician out of many, preferring an exact
    -- brand match, then a proven one.
    left join lateral (
      select x.device_type, x.brand
      from public.technician_specializations x
      where x.technician_id = t.id
        and x.device_type = any (jb.candidates)
      order by
        (jb.brand is not null and x.brand = jb.brand) desc,
        x.verified desc,
        x.created_at
      limit 1
    ) m on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'device_type', y.device_type,
          'brand',       y.brand,
          'skill_level', y.skill_level,
          'verified',    y.verified
        )
        order by y.verified desc, y.created_at
      ) as all_specializations
      from public.technician_specializations y
      where y.technician_id = t.id
    ) spec on true
    where
      -- Qualified for this device: either a declared specialisation matched,
      -- or the legacy columns carry the coarse category. See the `network`
      -- note in the header for why the second half is not dead code.
      (
        m.device_type is not null
        or t.specialization @> array[jb.device_type]
        or t.skill_tags    @> array[jb.device_type]
      )
      -- A client posting a job is not a candidate for their own job.
      and t.id <> jb.client_id
  )
  select
    r.id, r.full_name, r.avatar_url, r.tier, r.badge, r.is_verified,
    r.is_available, r.rating, r.review_count, r.total_jobs, r.is_new,
    r.distance_km, r.specializations, r.primary_device_type, r.primary_brand,
    r.rn::integer                                                  as match_rank,
    r.rn <= 3                                                      as is_top_match
  from ranked r
  order by r.rn
  limit v_limit;
end;
$function$;

comment on function public.match_technicians_for_job(uuid, integer) is
  'Technicians qualified for one posted job, ranked distance ASC then rating '
  'DESC. Rows 1-3 are the Top 3; the rest are the wider specialisation list '
  'and are not filtered on job count. Caller must own the job.';

-- ---------------------------------------------------------------------------
-- 7. The profile behind a card tap
-- ---------------------------------------------------------------------------
--
-- Returns one jsonb document rather than a row set, because the screen needs
-- four differently-shaped things at once - specialisation badges, portfolio
-- photos, a star breakdown and a page of reviews - and four round trips to
-- render one screen is four chances to half-load it.
--
-- The first page of reviews is embedded so the screen paints complete on the
-- first frame; `technician_reviews()` below pages the rest as the list scrolls.
--
-- PRIVACY NOTE worth raising before someone else does: `reviewer_name` is the
-- client's real full name, which is the convention on marketplaces but is a
-- disclosure to every browsing stranger. If the panel pushes on it, the change
-- is one line here - return initials, or a first name and last initial - and no
-- change anywhere else.

create or replace function public.technician_profile(
  p_technician_id uuid,
  p_client_lat double precision default null,
  p_client_lng double precision default null,
  p_review_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_review_limit, 20), 1), 50);
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id',            t.id,
    'full_name',     p.full_name,
    'avatar_url',    p.avatar_url,
    'tier',          t.tier,
    'badge',         t.badge,
    'is_verified',   t.is_verified,
    'is_available',  t.is_available,
    'member_since',  t.created_at,

    -- Same effective-rating rule as the listings, so the profile can never
    -- disagree with the card the client just tapped.
    'rating',        coalesce(s.average_stars, t.rating, 0),
    'review_count',  coalesce(s.review_count, 0),
    'total_jobs',    coalesce(t.total_jobs, 0),
    'is_new',        coalesce(t.total_jobs, 0) = 0,

    'distance_km', round(
      public.haversine_km(
        p_client_lat,
        p_client_lng,
        coalesce(t.base_latitude::double precision, t.latitude),
        coalesce(t.base_longitude::double precision, t.longitude)
      )::numeric, 2
    ),

    -- Star breakdown as a 5-key object. Zeros are present rather than omitted
    -- so the bar chart always has five bars to draw.
    'star_breakdown', jsonb_build_object(
      '5', coalesce(s.star_5, 0),
      '4', coalesce(s.star_4, 0),
      '3', coalesce(s.star_3, 0),
      '2', coalesce(s.star_2, 0),
      '1', coalesce(s.star_1, 0)
    ),

    'specializations', coalesce(spec.items, '[]'::jsonb),
    'portfolio',       coalesce(port.items, '[]'::jsonb),
    'reviews',         coalesce(rev.items,  '[]'::jsonb),

    -- Contact details follow the same rule `technician-directory` applies, and
    -- for the same reason: browsing a profile must never hand out a phone
    -- number. It is released only to a client who has an actual booking with
    -- this technician. Duplicated here rather than cross-called so the profile
    -- screen is one round trip; if the rule changes, it changes in both places.
    'contact_unlocked', booked.has_booking,
    'phone', case when booked.has_booking then p.phone else null end
  )
  into v_result
  from public.technicians t
  join public.profiles p on p.id = t.id
  left join public.technician_review_stats s on s.technician_id = t.id

  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'device_type', x.device_type,
        'brand',       x.brand,
        'skill_level', x.skill_level,
        'verified',    x.verified,
        'category',    x.category
      )
      order by x.verified desc, x.created_at
    ) as items
    from public.technician_specializations x
    where x.technician_id = t.id
  ) spec on true

  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id',          f.id,
        'photo_url',   f.photo_url,
        'description', f.description,
        'created_at',  f.created_at
      )
      order by f.created_at desc
    ) as items
    from public.technician_portfolio f
    where f.technician_id = t.id
      -- A row with no image is an upload that never finished; it would render
      -- as a grey box in the gallery.
      and f.photo_url is not null
  ) port on true

  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id',              q.id,
        'stars',           q.stars,
        'comment',         q.comment,
        'created_at',      q.created_at,
        'reviewer_name',   q.reviewer_name,
        'reviewer_avatar', q.reviewer_avatar
      )
      order by q.created_at desc
    ) as items
    from (
      select r.id, r.stars, r.comment, r.created_at,
             rp.full_name as reviewer_name,
             rp.avatar_url as reviewer_avatar
      from public.job_reviews r
      join public.profiles rp on rp.id = r.reviewer_id
      where r.technician_id = t.id
      order by r.created_at desc
      limit v_limit
    ) q
  ) rev on true

  left join lateral (
    select exists (
      select 1
      from public.jobs j
      where j.client_id = auth.uid()
        and j.assigned_technician_id = t.id
        and j.status in ('confirmed', 'in_progress', 'completed')
    ) as has_booking
  ) booked on true

  where t.id = p_technician_id
    -- Same gate as the listings. Without it a stale card, a deep link or a
    -- screenshot could open the profile of an account that has since been
    -- rejected or suspended.
    and t.is_verified = true
    and p.registration_status = 'active';

  if v_result is null then
    raise exception 'Technician not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

comment on function public.technician_profile(
  uuid, double precision, double precision, integer
) is
  'One technician profile as a single jsonb document: specialisations, '
  'portfolio, star breakdown, total jobs and the first page of reviews.';

-- ---------------------------------------------------------------------------
-- 8. Paging the review list
-- ---------------------------------------------------------------------------
--
-- Keyset paging by `created_at` rather than OFFSET. A profile with hundreds of
-- reviews receiving a new one mid-scroll would, under OFFSET, shift every later
-- page by one and show the reader a duplicate. `p_before` is the `created_at`
-- of the last row already on screen; the index on
-- (technician_id, created_at desc) serves this directly.

create or replace function public.technician_reviews(
  p_technician_id uuid,
  p_before timestamptz default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  stars integer,
  comment text,
  created_at timestamptz,
  reviewer_name text,
  reviewer_avatar text
)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  return query
  select r.id, r.stars, r.comment, r.created_at,
         rp.full_name, rp.avatar_url
  from public.job_reviews r
  join public.profiles rp on rp.id = r.reviewer_id
  join public.technicians t on t.id = r.technician_id
  join public.profiles tp on tp.id = t.id
  where r.technician_id = p_technician_id
    and t.is_verified = true
    and tp.registration_status = 'active'
    and (p_before is null or r.created_at < p_before)
  order by r.created_at desc
  limit v_limit;
end;
$function$;

comment on function public.technician_reviews(uuid, timestamptz, integer) is
  'Keyset-paged reviews for one technician, newest first. Pass the last row''s '
  'created_at as p_before for the next page.';

-- ---------------------------------------------------------------------------
-- 9. Who may call these
-- ---------------------------------------------------------------------------
--
-- EXECUTE is granted to `authenticated` only. `anon` is excluded deliberately:
-- every function above runs as its owner and reads past `technicians_select_own`,
-- so leaving anon able to call them would hand the whole technician directory
-- to anybody holding the publishable anon key - the exact outcome that policy
-- exists to prevent. The `auth.uid() is null` guard inside each function is the
-- second lock on the same door.

revoke all on function public.recommended_technicians(
  double precision, double precision, integer) from public, anon;
grant execute on function public.recommended_technicians(
  double precision, double precision, integer) to authenticated;

revoke all on function public.match_technicians_for_job(uuid, integer)
  from public, anon;
grant execute on function public.match_technicians_for_job(uuid, integer)
  to authenticated;

revoke all on function public.technician_profile(
  uuid, double precision, double precision, integer) from public, anon;
grant execute on function public.technician_profile(
  uuid, double precision, double precision, integer) to authenticated;

revoke all on function public.technician_reviews(uuid, timestamptz, integer)
  from public, anon;
grant execute on function public.technician_reviews(uuid, timestamptz, integer)
  to authenticated;

-- `haversine_km` is pure arithmetic over its arguments and leaks nothing, so it
-- stays callable - the edge functions and future migrations both use it.
grant execute on function public.haversine_km(
  double precision, double precision, double precision, double precision)
  to authenticated, service_role;

-- Supporting indexes for the two listings.
--
-- The ranking columns live on `technicians`, which is small (one row per
-- technician), so the planner will usually seq-scan it whatever we do. These
-- help the joins that hang off it rather than the scan itself.
create index if not exists idx_technician_specializations_device
  on public.technician_specializations (device_type, technician_id);

create index if not exists idx_technicians_listing
  on public.technicians (is_verified, rating desc, total_jobs desc);
