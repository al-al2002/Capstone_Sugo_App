-- SUGO: rank the dashboard's recommended row on evidence, not on a bare average
--
-- ---------------------------------------------------------------------------
-- WHAT WAS WRONG
-- ---------------------------------------------------------------------------
--
-- `recommended_technicians` ordered by:
--
--     coalesce(s.average_stars, t.rating, 0) desc,
--     coalesce(t.total_jobs, 0) desc
--
-- Rating first, with no regard for how much evidence is behind it. So a
-- technician with ONE five-star review outranked one with 4.8 across two
-- hundred completed jobs - on a row whose whole purpose is to answer "who is
-- good here?".
--
-- That is not a cosmetic ordering problem. It is the classic small-sample
-- failure, and on a marketplace it is actively harmful: the cheapest way to
-- reach the top of the list becomes "have almost no history", which is the
-- opposite of what the row is meant to surface, and it is trivially gamed by
-- one review from a friend.
--
-- Job count as a *tie-break* did not save it either. Ties on a numeric average
-- are rare, so the second term almost never ran.
--
-- ---------------------------------------------------------------------------
-- THE FIX: A CREDIBILITY-WEIGHTED RATING
-- ---------------------------------------------------------------------------
--
-- A Bayesian average - the same shrinkage IMDb uses for its Top 250, and the
-- standard answer to this problem:
--
--                 v                m
--     score =  ------- * R  +  ------- * C
--               v + m           v + m
--
--     R = this technician's own average rating
--     v = how many reviews it is based on
--     C = the platform-wide mean rating
--     m = how many reviews a rating needs before it stands on its own
--
-- Read it as: a rating is trusted in proportion to the evidence behind it, and
-- what it is not trusted for is filled in with the platform average. One
-- five-star review barely moves a technician off the mean. Fifty reviews put
-- them almost entirely on their own record.
--
-- The important property is that it is not a fudge factor: as v grows the
-- score converges on R exactly, so a genuinely excellent technician with real
-- history ends up where they belong. It only ever penalises *absence of
-- evidence*, never a bad record.
--
-- ---------------------------------------------------------------------------
-- AND AN EXPERIENCE TERM, BECAUSE COMPLETED WORK IS THE OTHER HALF
-- ---------------------------------------------------------------------------
--
-- Reviews and completed jobs are not the same thing - plenty of finished jobs
-- are never reviewed - and the brief for this row is "many completed jobs AND
-- a high rating", so volume has to count for something on its own.
--
-- It is log-scaled and capped:
--
--   * `ln` because the difference between 2 jobs and 20 is real, and the
--     difference between 200 and 220 is noise. Linear volume would turn the
--     row into a leaderboard of whoever has been on the platform longest.
--
--   * capped at +0.30 (on a 0-5 scale) so experience can break a near-tie but
--     can never outrank a materially better record. A veteran with a mediocre
--     rating must not sit above a very good technician with a shorter history.
--
-- ---------------------------------------------------------------------------
-- WHY NEW TECHNICIANS ARE STILL NOT FILTERED OUT
-- ---------------------------------------------------------------------------
--
-- Tempting, and wrong. A hard `total_jobs > 0` filter empties this row
-- completely on a young platform, and it denies every new technician the only
-- surface that could give them a first job - which is how a marketplace
-- calcifies into the same five names for ever.
--
-- They are not filtered; they are simply ranked where the evidence puts them.
-- The scoring already does that honestly: no reviews means the score sits at
-- the platform mean, and no completed jobs means no experience bonus. They
-- appear below the proven ones, not nowhere.
--
-- Note this changes ONLY the ORDER BY. Same signature, same return type, same
-- columns, same WHERE clause - so nothing downstream has to know.

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

  -- Reviews before a rating stands on its own.
  --
  -- Five is a judgement call, and the honest way to describe it: low enough
  -- that a real technician escapes the mean within their first week of work,
  -- high enough that a single arranged review cannot buy the top of the list.
  v_m constant numeric := 5;

  -- The platform mean, computed once per call rather than per row.
  v_c numeric;
begin
  if auth.uid() is null then
    raise exception 'Sign in required'
      using errcode = '42501';
  end if;

  -- Only technicians with at least one review contribute to the mean;
  -- otherwise unrated accounts would drag it toward zero and the shrinkage
  -- would punish everybody. The 4.5 fallback covers a platform with no
  -- reviews at all, where every technician shrinks to the same value and the
  -- experience term decides - which is the right behaviour on day one.
  select coalesce(avg(average_stars), 4.5)
    into v_c
  from public.technician_review_stats
  where review_count > 0;

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
  order by
    (
      -- Credibility-weighted rating.
      (
        (coalesce(s.review_count, 0)::numeric
           * coalesce(s.average_stars, t.rating, 0)::numeric)
        + (v_m * v_c)
      ) / (coalesce(s.review_count, 0)::numeric + v_m)

      -- Experience, log-scaled and capped at +0.30.
      + least(ln(1 + coalesce(t.total_jobs, 0)::numeric) * 0.06, 0.30)
    ) desc,
    -- Completed work breaks a tie on the composite, so of two technicians
    -- scoring alike the busier one leads.
    coalesce(t.total_jobs, 0) desc,
    -- Deterministic final tie-break, so paging cannot show the same
    -- technician twice.
    t.id
  limit v_limit;
end;
$function$;

comment on function public.recommended_technicians(
  double precision, double precision, integer
) is
  'Dashboard "best performers": every verified, active technician ranked by a '
  'credibility-weighted rating (Bayesian shrinkage toward the platform mean, '
  'm=5) plus a capped log experience bonus for completed jobs, then by total '
  'jobs. A five-star rating from one review can no longer outrank a long, '
  'strong record. Coordinates are for display distance only and do not affect '
  'ordering.';
