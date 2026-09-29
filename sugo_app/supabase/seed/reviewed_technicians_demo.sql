-- SUGO: give demo technicians a real job history, so the recommended row fills
--
-- Run this in the Supabase SQL Editor. It is a seed script, not a migration:
-- it is not in supabase/migrations/ and `supabase db push` will not run it.
--
-- ---------------------------------------------------------------------------
-- WHY `technicians_demo.sql` IS NOT ENOUGH ON ITS OWN
-- ---------------------------------------------------------------------------
--
-- That script sets `technicians.rating = 4.90` and `total_jobs = 152`, which
-- looks like a well-reviewed technician and is not one.
--
-- Since migration 20260921000007 the recommended row requires:
--
--     total_jobs >= 20  AND  technician_review_stats.average_stars >= 4.0
--
-- and `technician_review_stats` is a VIEW over `job_reviews`. A technician
-- with no review rows has `average_stars = NULL`, and `NULL >= 4.0` is NULL,
-- not true - so they do not qualify no matter what the `rating` column says.
--
-- That is the intended behaviour: the `rating` column is a denormalised
-- convenience, and the threshold deliberately reads the source of truth
-- instead. It does mean a demo needs real reviews, which is what this creates.
--
-- ---------------------------------------------------------------------------
-- WHAT IT CREATES
-- ---------------------------------------------------------------------------
--
-- For each of the first 3 verified, active technicians:
--
--   * 20 completed jobs, assigned to them, posted by a demo client
--   * 20 reviews - twelve 5-star and eight 4-star, so the average lands at
--     4.60 rather than a suspicious flat 5.00
--   * `total_jobs` updated to match the jobs that actually exist
--
-- Every row it writes is tagged `[DEMO SEED]` in `jobs.description`, so the
-- cleanup at the bottom of this file removes all of it and nothing else.
--
-- ---------------------------------------------------------------------------
-- WHAT YOU NEED FIRST
-- ---------------------------------------------------------------------------
--
-- `jobs.client_id` and `job_reviews.reviewer_id` both reference `profiles`,
-- which references `auth.users`. Accounts cannot be invented here - they have
-- to be real. So before running this you need, signed up through the app:
--
--   * at least one CLIENT account (it becomes the reviewer), and
--   * at least one TECHNICIAN account, verified and active
--     (`technicians_demo.sql` promotes profiles into technicians).
--
-- The script checks for both and stops with a clear notice if either is
-- missing, rather than half-seeding.

do $$
declare
  v_client   uuid;
  v_techs    uuid[];
  v_tech     uuid;
  v_job      uuid;
  v_stars    integer;
  v_made     integer;
  i          integer;

  -- 20 jobs each, which is exactly the threshold in
  -- `recommended_technicians`. Deliberately not 25: seeding right on the line
  -- proves the rule admits at the boundary rather than hiding a rounding bug.
  c_jobs constant integer := 20;

  -- Rotated through so the history looks like real work rather than a wall of
  -- identical rows.
  c_devices  constant text[] := array['laptop','phone','appliance','network'];
  c_symptoms constant text[] := array[
    'Screen cracked after a drop',
    'Will not power on',
    'Overheating and shutting down',
    'No internet after a storm',
    'Battery drains in an hour',
    'Making a loud noise when running'
  ];
begin
  -- ---------------------------------------------------------------- client
  select p.id into v_client
  from public.profiles p
  where p.role = 'client'
  order by p.created_at
  limit 1;

  if v_client is null then
    raise notice
      'STOPPED: no client account found. Sign up a client through the app '
      'first - it becomes the reviewer on every seeded job.';
    return;
  end if;

  -- ----------------------------------------------------------- technicians
  select array_agg(t.id order by t.created_at)
  into v_techs
  from public.technicians t
  join public.profiles p on p.id = t.id
  where t.is_verified = true
    and p.registration_status = 'active'
    and t.id <> v_client;          -- never let anybody review themselves

  if v_techs is null or array_length(v_techs, 1) < 1 then
    raise notice
      'STOPPED: no verified, active technician found. Run '
      'technicians_demo.sql first, and make sure profiles.registration_status '
      'is ''active'' for them.';
    return;
  end if;

  raise notice 'Client % will review % technician(s).',
    v_client, array_length(v_techs, 1);

  -- ------------------------------------------------------------ the history
  foreach v_tech in array v_techs[1:3] loop
    v_made := 0;

    for i in 1..c_jobs loop
      insert into public.jobs (
        client_id,
        device_type,
        problem_symptom,
        has_physical_damage,
        service_path,
        urgency,
        status,
        assigned_technician_id,
        description,
        latitude,
        longitude,
        created_at
      ) values (
        v_client,
        c_devices[1 + (i % array_length(c_devices, 1))],
        c_symptoms[1 + (i % array_length(c_symptoms, 1))],
        false,
        'home_service',
        'can_wait',
        'completed',
        v_tech,
        '[DEMO SEED] Backfilled history for the recommended row.',
        7.0731,
        125.6128,
        -- Spread backwards through the last few months, so "member since" and
        -- any recency logic have something sensible to read.
        now() - ((i * 5) || ' days')::interval
      )
      returning id into v_job;

      -- Twelve 5s and eight 4s -> an average of 4.60.
      v_stars := case when i <= 12 then 5 else 4 end;

      -- The outcome row goes in BEFORE the review, and the order is not
      -- cosmetic.
      --
      -- Inserting a review fires `sync_review_to_scoring`, which does
      -- `update job_outcomes set final_rating = new.stars` and then calls
      -- `recompute_technician_rating`. That recompute averages
      -- `job_outcomes.final_rating` and **coalesces an empty result to 0**.
      --
      -- So with no outcome row the update matches nothing, the average is
      -- empty, and the trigger sets `technicians.rating = 0` - quietly wiping
      -- the 4.90 that `technicians_demo.sql` had just written. Seeding
      -- reviews would make the rating column worse, not better.
      --
      -- Creating the outcome first means the trigger finds a row to stamp and
      -- recomputes the real 4.60. It also gives RB-CARS' accuracy scoring the
      -- history it reads, so the seeded technicians behave properly in the
      -- matching flow too, not only on the recommended row.
      insert into public.job_outcomes (
        job_id, technician_id, diagnosis_correct, rerouted_mid_job, created_at
      ) values (
        v_job,
        v_tech,
        -- Mostly right, occasionally not. A perfect record would make the
        -- diagnosis-accuracy term in Stage 2 untestable.
        (i % 7) <> 0,
        false,
        now() - ((i * 5) || ' days')::interval + interval '1 hour'
      );

      insert into public.job_reviews (
        job_id, technician_id, reviewer_id, stars, comment, created_at
      ) values (
        v_job,
        v_tech,
        v_client,
        v_stars,
        case
          when v_stars = 5 then 'Fast, tidy work and explained the fix clearly.'
          else 'Good job overall, arrived a little later than agreed.'
        end,
        now() - ((i * 5) || ' days')::interval + interval '2 hours'
      )
      on conflict (job_id, reviewer_id) do nothing;

      v_made := v_made + 1;
    end loop;

    -- Keep the denormalised counter honest with the rows just created, rather
    -- than assigning a flattering number. `total_jobs` is what the threshold
    -- reads, so it has to mean what it says.
    update public.technicians t
    set total_jobs = (
      select count(*) from public.jobs j
      where j.assigned_technician_id = t.id
        and j.status = 'completed'
    )
    where t.id = v_tech;

    raise notice 'Technician %: % completed jobs and reviews seeded.',
      v_tech, v_made;
  end loop;

  raise notice 'Done. Pull to refresh the client dashboard.';
end $$;

-- ---------------------------------------------------------------------------
-- Did it work? This is the same test `recommended_technicians` applies.
-- ---------------------------------------------------------------------------

select
  p.full_name,
  t.total_jobs,
  s.review_count,
  s.average_stars,
  (coalesce(t.total_jobs, 0) >= 20 and s.average_stars >= 4.0)
    as would_be_recommended
from public.technicians t
join public.profiles p on p.id = t.id
left join public.technician_review_stats s on s.technician_id = t.id
where t.is_verified = true
  and p.registration_status = 'active'
order by would_be_recommended desc nulls last, s.average_stars desc nulls last;

-- ---------------------------------------------------------------------------
-- CLEANUP - removes everything this script created, and nothing else
-- ---------------------------------------------------------------------------
--
-- `job_reviews.job_id` cascades on delete, so removing the tagged jobs removes
-- their reviews with them. The counter is then recomputed from what is left.
--
--   delete from public.jobs
--   where description = '[DEMO SEED] Backfilled history for the recommended row.';
--
--   update public.technicians t
--   set total_jobs = (
--     select count(*) from public.jobs j
--     where j.assigned_technician_id = t.id and j.status = 'completed'
--   );
