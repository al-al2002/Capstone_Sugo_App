-- SUGO: what kind of work a technician takes - Home Service, Shop Repair, or
-- both (2026-11-17)
--
-- Approved by the user on 2026-11-17: "2 columns on technicians" (one of the
-- four frozen RB-CARS tables - asked first), and "the already registered
-- technician make it both home service and shop repair".
--
-- ## Why
--
-- Until now every technician was matched to every kind of job. A client who
-- picked Shop Repair could be offered someone with no shop, and a client who
-- picked Home Service someone who only works at a bench. Registration now
-- asks which work they take (both is allowed), and matching only offers a
-- job to technicians who take that kind of work.
--
-- ## What changes
--
-- 1. `technicians.offers_home_service` and `offers_shop_repair`, booleans,
--    NOT NULL, default true, and at least one must be true.
-- 2. Every technician already registered is set to both - explicitly, below,
--    as the user asked - so nobody drops out of matching.
-- 3. `matching_candidates` carries the two columns; `match-technician` gates
--    on them in Stage 1 (Home Service -> offers_home_service, Shop Repair ->
--    offers_shop_repair).
-- 4. `match_technicians_for_job` (the "more technicians" list, ranks 4+)
--    applies the same gate, so the two lists cannot disagree.
--
-- No RLS change. A technician writes their own row through the existing
-- update policy; `guard_technician_self_update()` lists the columns they may
-- NOT touch, and these are not among them - a technician choosing their own
-- kind of work is exactly what it should allow.
--
-- A Shop Repair technician's shop location is the existing `shop_latitude` /
-- `shop_longitude` / `shop_name` (20260917000003); registration now asks for
-- it when Shop Repair is chosen.

-- ---------------------------------------------------------------------------
-- 1. The columns
-- ---------------------------------------------------------------------------

alter table public.technicians
  add column if not exists offers_home_service boolean not null default true,
  add column if not exists offers_shop_repair boolean not null default true;

alter table public.technicians
  drop constraint if exists technicians_offers_some_work;
alter table public.technicians
  add constraint technicians_offers_some_work
  check (offers_home_service or offers_shop_repair);

comment on column public.technicians.offers_home_service is
  'Takes Home Service jobs: travels to the client and repairs on site. '
  'Matching only offers home_service jobs to technicians with this true.';
comment on column public.technicians.offers_shop_repair is
  'Takes Shop Repair jobs: repairs at their own shop (shop_latitude / '
  'shop_longitude). Matching only offers pickup jobs to technicians with this '
  'true.';

-- ---------------------------------------------------------------------------
-- 2. Everyone already registered does both (the user's instruction)
-- ---------------------------------------------------------------------------
--
-- The defaults above already fill both columns with true for every existing
-- row; this states it, and touches only a row that somehow is not.

update public.technicians
set offers_home_service = true,
    offers_shop_repair = true
where not (offers_home_service and offers_shop_repair);

-- ---------------------------------------------------------------------------
-- 3. The candidate pool carries them
-- ---------------------------------------------------------------------------
--
-- Copied from 20261109000001; only the two appended columns are new.

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
  t.latitude,
  t.longitude,
  t.base_latitude,
  t.base_longitude,
  t.service_radius_km,
  t.verification_tier,
  t.created_at,
  p.full_name,
  p.avatar_url,
  p.phone,
  exists (
    select 1
    from public.identity_verifications iv
    where iv.user_id = t.id
      and iv.status = 'approved'
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
  public.technician_away_until(t.id) as away_until,
  t.barangay,
  -- NEW (20261117000007): what kind of work they take. Appended, as a
  -- replaced view may only add columns at the end.
  t.offers_home_service,
  t.offers_shop_repair
from public.technicians t
join public.profiles p on p.id = t.id;

revoke all on public.matching_candidates from anon, authenticated;
grant select on public.matching_candidates to service_role;

-- ---------------------------------------------------------------------------
-- 4. The wider match list applies the same gate
-- ---------------------------------------------------------------------------
--
-- Copied from 20260916000001; only the lines marked NEW are new.

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
      j.service_path,  -- NEW (20261117000007), for the work-type gate
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
      -- NEW (20261117000007): only technicians who take this kind of
      -- work. Home Service -> offers_home_service, Shop Repair ->
      -- offers_shop_repair. The same gate as the engine's Stage 1, so
      -- the Top 3 and the wider list can never disagree.
      and case jb.service_path
            when 'home_service' then t.offers_home_service
            when 'pickup' then t.offers_shop_repair
            else true
          end
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

revoke all on function public.match_technicians_for_job(uuid, integer)
  from public, anon;
grant execute on function public.match_technicians_for_job(uuid, integer)
  to authenticated;
