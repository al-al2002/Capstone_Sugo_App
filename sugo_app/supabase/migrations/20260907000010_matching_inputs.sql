-- SUGO: give RB-CARS the registration data it now needs to match on
--
-- Stage 1 is being extended to match on brand and device type, to gate on
-- identity approval, and to respect each technician's own service radius.
-- Three things stood in the way, and this migration removes them.
--
-- ## Gap 1: a job had no brand
--
-- `technician_specializations` records (device_type, brand). `jobs` recorded
-- no brand at all, so "match the technician's brand to the job's brand" had
-- nothing on the job side to compare against. `jobs.brand` is added below.
--
-- ## Gap 2: the two device vocabularies did not overlap
--
-- This is the one that would have quietly produced zero matches.
--
--   jobs.device_type                     laptop | phone | appliance | network
--   technician_specializations.device_type
--     laptop, desktop, smartphone, tablet, printer, aircon, refrigerator,
--     washing_machine, television, microwave
--
-- An equality test between them matches only the word "laptop". A technician
-- who declared `desktop` or `aircon` could never match any job, however well
-- qualified - the filter would have silently excluded most of the platform.
--
-- Rather than rewrite `jobs.device_type` (it is part of the frozen RB-CARS
-- four-table schema, the Flutter posting flow writes it, and the accuracy
-- index is keyed on it), a nullable `device_detail` is added alongside it for
-- the precise device, and `job_device_candidates()` maps the coarse value onto
-- the set of fine ones when `device_detail` is absent. Old jobs keep matching;
-- new ones can be exact.
--
-- ## Gap 3: the matcher could not see the new tables in one read
--
-- The candidate query reads `technicians` with a PostgREST embed. It cannot
-- reach `identity_verifications` that way - there is no direct foreign key
-- from `technicians` to it, only a shared id through `profiles`. The
-- `matching_candidates` view below pre-joins everything Stage 1 and Stage 2
-- need, so the engine still makes one query.

-- ---------------------------------------------------------------------------
-- 1. Brand and precise device on a job
-- ---------------------------------------------------------------------------

alter table public.jobs
  add column if not exists brand text;

comment on column public.jobs.brand is
  'Brand of the device to repair, matching technician_specializations.brand. '
  'Null or "Others" means the client did not say, and Stage 1 falls back to '
  'matching on device type alone rather than excluding everybody.';

alter table public.jobs
  add column if not exists device_detail text;

comment on column public.jobs.device_detail is
  'Precise device type, from the same vocabulary as '
  'technician_specializations.device_type. Nullable: `device_type` stays the '
  'coarse value the RB-CARS schema froze, and job_device_candidates() maps it '
  'when this is not set.';

-- Filtering candidates by brand is a common lookup once matching uses it.
create index if not exists idx_jobs_brand on public.jobs (brand)
  where brand is not null;

-- ---------------------------------------------------------------------------
-- 2. Reconciling the two device vocabularies
-- ---------------------------------------------------------------------------
--
-- Returns the set of `technician_specializations.device_type` values that
-- could serve this job.
--
--   * `device_detail` set  -> exactly that one device.
--   * otherwise            -> every fine device the coarse category covers.
--
-- KNOWN GAP, stated rather than hidden: `printer` belongs to no coarse
-- category, because `jobs.device_type` has no value for it. A printer job can
-- only be matched precisely by setting `device_detail`, and the Flutter job
-- posting flow does not offer that yet. Until it does, a printer job posted as
-- `laptop` will match computer technicians, not printer specialists.
--
-- `network` maps to the empty set: no device in the specialisation catalogue
-- covers it, so no technician can claim a brand-level match for it and every
-- candidate falls to the general tier. That is the honest answer, not a bug.

create or replace function public.job_device_candidates(
  p_device_type text,
  p_device_detail text default null
)
returns text[]
language sql
immutable
as $function$
  select case
    when coalesce(trim(p_device_detail), '') <> '' then array[p_device_detail]
    when p_device_type = 'laptop'    then array['laptop', 'desktop']
    when p_device_type = 'phone'     then array['smartphone', 'tablet']
    when p_device_type = 'appliance' then array[
      'aircon', 'refrigerator', 'washing_machine', 'television', 'microwave'
    ]
    else array[]::text[]
  end;
$function$;

comment on function public.job_device_candidates(text, text) is
  'Maps a job onto the technician_specializations.device_type values that can '
  'serve it. Bridges the coarse jobs vocabulary and the fine specialisation '
  'one so a brand/device filter does not silently exclude most technicians.';

-- ---------------------------------------------------------------------------
-- 3. One read for the whole candidate pool
-- ---------------------------------------------------------------------------
--
-- Everything Stage 1 and Stage 2 consume, joined once. Specialisations are
-- aggregated into jsonb rather than returned as rows so the engine still gets
-- one record per technician and does not have to regroup them in TypeScript.
--
-- `identity_approved` is computed here because it is a hard gate. Note it is
-- *not* redundant with `is_verified`: `activate_account()` only sets
-- `is_verified` when identity is approved AND an assessment was passed, so
-- today the two move together - but they mean different things, and a future
-- change to one must not silently open the other. Stage 1 checks both.

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
  ) as specializations
from public.technicians t
join public.profiles p on p.id = t.id;

comment on view public.matching_candidates is
  'The RB-CARS candidate pool with identity status, base location, service '
  'radius, verification tier and declared specialisations already joined. '
  'Read by match-technician on the service role.';

revoke all on public.matching_candidates from anon, authenticated;
grant select on public.matching_candidates to service_role;

-- ---------------------------------------------------------------------------
-- 4. Client trust, for Stage 2
-- ---------------------------------------------------------------------------
--
-- Stage 2 weighs how likely a technician is to accept. A client with a history
-- of no-shows is a real cost to a technician who travels across the city, so
-- trust level becomes a soft factor.
--
-- Deliberately a *view over the job*, so the engine reads the client's trust
-- alongside the job it already fetched instead of making a second query per
-- match. `trust_level` is null for a client with no row yet, which the engine
-- treats as 'new'.

create or replace view public.job_client_trust as
select
  j.id as job_id,
  j.client_id,
  coalesce(cvs.trust_level, 'new') as trust_level,
  coalesce(cvs.no_show_count, 0)   as no_show_count,
  cvs.avg_rating_from_technicians,
  coalesce(cvs.phone_verified, false) as phone_verified
from public.jobs j
left join public.client_verification_status cvs on cvs.client_id = j.client_id;

revoke all on public.job_client_trust from anon, authenticated;
grant select on public.job_client_trust to service_role;
