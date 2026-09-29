-- SUGO: a technician must earn their way into the recommended row
--
-- Requested rule: 20 completed jobs, and good reviews on them, before anyone
-- appears on the client dashboard's "Recommended technicians" row.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS REVERSES, AND WHY THAT IS FINE
-- ---------------------------------------------------------------------------
--
-- Migration 20260921000006 argued *against* a hard threshold, on the grounds
-- that it denies newcomers the one surface that could win them a first job.
-- That argument was heard and overruled, and the counter-argument is good:
--
--   "Recommended" is a promise the platform makes in its own voice. A client
--   reading that row is being told *we vouch for these people*. Vouching for
--   somebody with four jobs and one review is a promise the data cannot keep,
--   and the cost of breaking it - a bad first repair on a recommendation -
--   lands on the client and on SUGO, not on the technician.
--
-- Discovery for newcomers is not actually lost. It was never this row's job:
--
--   * `match_technicians_for_job` ranks everyone whose specialisation fits,
--     with no job-count filter at all, and that is the surface that actually
--     produces bookings.
--   * The full ranking below the Top 3 on the review screen includes
--     technicians with no history whatsoever, deliberately.
--
-- So the threshold applies HERE and nowhere else. Matching keeps its open
-- door; this row becomes a shortlist rather than a directory.

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

  -- ------------------------------------------------------ the entry rules
  --
  -- Both named, so tuning them is a one-line change rather than an
  -- archaeology exercise through an ORDER BY.

  -- Completed jobs before the platform will vouch for somebody.
  v_min_jobs constant integer := 20;

  -- What "good reviews" means, on the 1-5 scale used by `job_reviews`.
  --
  -- 4.0 rather than 4.5: star ratings on marketplaces cluster high, so 4.5
  -- would admit almost nobody and would make the row a near-duplicate of the
  -- top two or three names. 4.0 excludes the genuinely mediocre while leaving
  -- a real shortlist.
  --
  -- Note this comparison also does the work of "must actually be reviewed":
  -- `average_stars` is NULL for a technician with no reviews, and
  -- `NULL >= 4.0` is NULL, not true - so twenty unreviewed jobs do not
  -- qualify. That is the intended reading of "the 20 jobs should have good
  -- reviews".
  v_min_rating constant numeric := 4.0;

  -- Ranking constants, unchanged from 20260921000006.
  v_m constant numeric := 5;
  v_c numeric;
begin
  if auth.uid() is null then
    raise exception 'Sign in required'
      using errcode = '42501';
  end if;

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
      2
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
    and p.registration_status = 'active'
    -- ----------------------------------------------------- the threshold
    and coalesce(t.total_jobs, 0) >= v_min_jobs
    and s.average_stars >= v_min_rating
  -- Ranking is unchanged: a credibility-weighted rating plus a capped log
  -- experience term. It still matters - the threshold decides *who is
  -- eligible*, this decides *who leads* - and among a pool that has all
  -- cleared 20 jobs the shrinkage has little left to correct, which is
  -- exactly as it should be.
  order by
    (
      (
        (coalesce(s.review_count, 0)::numeric
           * coalesce(s.average_stars, t.rating, 0)::numeric)
        + (v_m * v_c)
      ) / (coalesce(s.review_count, 0)::numeric + v_m)
      + least(ln(1 + coalesce(t.total_jobs, 0)::numeric) * 0.06, 0.30)
    ) desc,
    coalesce(t.total_jobs, 0) desc,
    t.id
  limit v_limit;
end;
$function$;

comment on function public.recommended_technicians(
  double precision, double precision, integer
) is
  'Dashboard "best performers". ENTRY RULE: at least 20 completed jobs AND a '
  'review average of 4.0 or better (an unreviewed technician has a NULL '
  'average and does not qualify). Those who clear it are ranked by a '
  'credibility-weighted rating plus a capped log experience bonus. The '
  'threshold applies to this row only - `match_technicians_for_job` still '
  'ranks every qualified technician regardless of history.';

-- ---------------------------------------------------------------------------
-- How many technicians clear the bar right now
-- ---------------------------------------------------------------------------
--
-- Run this in the SQL editor before a demo. If it returns 0, the recommended
-- row will be empty - correctly, but empty - and either the seed data needs
-- more completed jobs or `v_min_jobs` needs lowering for the demo.
--
--   select
--     count(*) filter (where t.is_verified and p.registration_status = 'active')
--       as active_technicians,
--     count(*) filter (where coalesce(t.total_jobs,0) >= 20)
--       as have_20_jobs,
--     count(*) filter (where coalesce(t.total_jobs,0) >= 20
--                        and s.average_stars >= 4.0)
--       as would_be_recommended
--   from public.technicians t
--   join public.profiles p on p.id = t.id
--   left join public.technician_review_stats s on s.technician_id = t.id;
