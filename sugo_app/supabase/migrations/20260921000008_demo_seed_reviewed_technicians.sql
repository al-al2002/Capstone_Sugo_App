-- SUGO: DEMO DATA - give technicians a real job history so the recommended
--        row has somebody to show
--
-- ---------------------------------------------------------------------------
-- THIS IS A SEED, SHIPPED AS A MIGRATION
-- ---------------------------------------------------------------------------
--
-- Demo rows do not normally belong in migration history - a migration is
-- schema, and this writes jobs and reviews. It is here because `db push` is
-- the only way to run SQL against this project from the toolchain available,
-- and the identical script in `supabase/seed/` requires pasting into the SQL
-- Editor by hand.
--
-- Consequences to be aware of:
--
--   * It runs on every fresh deploy of this project. For a capstone that is
--     arguably a feature - the demo reproduces itself - but it is the reason
--     this file is named `demo_seed` rather than hiding behind a neutral name.
--   * It is IDEMPOTENT. Re-running `db push` cannot double the history,
--     because it skips any technician that already has seeded jobs.
--   * Everything it writes is tagged, and the last section of this file is the
--     single statement that removes all of it.
--
-- ---------------------------------------------------------------------------
-- WHY THE RECOMMENDED ROW WAS EMPTY
-- ---------------------------------------------------------------------------
--
-- Migration 20260921000007 requires:
--
--     total_jobs >= 20  AND  technician_review_stats.average_stars >= 4.0
--
-- `technician_review_stats` is a VIEW over `job_reviews`. The existing demo
-- seed (`supabase/seed/technicians_demo.sql`) sets `technicians.rating = 4.90`
-- and creates NO review rows - so `average_stars` is NULL, `NULL >= 4.0` is
-- NULL rather than true, and nobody qualifies however good the `rating` column
-- looks. The threshold reads the source of truth on purpose.
--
-- ---------------------------------------------------------------------------
-- WHY job_outcomes IS WRITTEN BEFORE job_reviews
-- ---------------------------------------------------------------------------
--
-- Inserting a review fires `sync_review_to_scoring`, which does
-- `update job_outcomes set final_rating = new.stars` and then calls
-- `recompute_technician_rating`. That recompute averages
-- `job_outcomes.final_rating` and coalesces an empty result to 0.
--
-- With no outcome row the update matches nothing and the trigger sets
-- `technicians.rating = 0` - wiping the rating the other seed just wrote.
-- Creating the outcome first lets the trigger stamp it and recompute the real
-- average, and gives RB-CARS' accuracy scoring the history it reads.

do $$
declare
  v_client     uuid;
  v_techs      uuid[];
  v_tech       uuid;
  v_job        uuid;
  v_stars      integer;
  v_existing   integer;
  v_seeded     integer := 0;
  i            integer;

  c_jobs constant integer := 20;
  c_tag  constant text    := '[DEMO SEED] Backfilled history for the recommended row.';

  c_devices  constant text[] := array['laptop','phone','appliance','network'];
  c_symptoms constant text[] := array[
    'Screen cracked after a drop',
    'Will not power on',
    'Overheating and shutting down',
    'No internet after a storm',
    'Battery drains in an hour',
    'Making a loud noise when running'
  ];

  -- Diagnostics, so a no-op explains itself in the push output instead of
  -- looking like the migration did nothing.
  d_profiles   integer;
  d_clients    integer;
  d_techs_all  integer;
  d_techs_ok   integer;
begin
  select count(*) into d_profiles  from public.profiles;
  select count(*) into d_clients   from public.profiles where role = 'client';
  select count(*) into d_techs_all from public.technicians;
  select count(*) into d_techs_ok
  from public.technicians t
  join public.profiles p on p.id = t.id
  where t.is_verified = true and p.registration_status = 'active';

  raise notice '--- SUGO demo seed -------------------------------------';
  raise notice 'profiles: %, clients: %, technicians: %, verified+active: %',
    d_profiles, d_clients, d_techs_all, d_techs_ok;

  -- ---------------------------------------------------------------- client
  select p.id into v_client
  from public.profiles p
  where p.role = 'client'
  order by p.created_at
  limit 1;

  if v_client is null then
    raise notice 'SKIPPED: no client account exists, and jobs.client_id plus';
    raise notice '         job_reviews.reviewer_id both need a real profile.';
    raise notice '         Sign up a CLIENT through the app, then push again.';
    return;
  end if;

  -- ----------------------------------------------------------- technicians
  select array_agg(t.id order by t.created_at)
  into v_techs
  from public.technicians t
  join public.profiles p on p.id = t.id
  where t.is_verified = true
    and p.registration_status = 'active'
    and t.id <> v_client;            -- nobody reviews themselves

  if v_techs is null or array_length(v_techs, 1) < 1 then
    raise notice 'SKIPPED: no verified, ACTIVE technician found.';
    raise notice '         Needs technicians.is_verified = true AND';
    raise notice '         profiles.registration_status = ''active''.';
    raise notice '         % technician row(s) exist but none qualify.',
      d_techs_all;
    return;
  end if;

  -- ------------------------------------------------------------ the history
  foreach v_tech in array v_techs[1:3] loop
    -- Idempotence: a technician that already has seeded jobs is left alone,
    -- so re-pushing cannot stack a second history on top of the first.
    select count(*) into v_existing
    from public.jobs j
    where j.assigned_technician_id = v_tech and j.description = c_tag;

    if v_existing > 0 then
      raise notice 'technician %: already has % seeded job(s), skipping.',
        v_tech, v_existing;
      continue;
    end if;

    for i in 1..c_jobs loop
      insert into public.jobs (
        client_id, device_type, problem_symptom, has_physical_damage,
        service_path, urgency, status, assigned_technician_id, description,
        latitude, longitude, created_at
      ) values (
        v_client,
        c_devices[1 + (i % array_length(c_devices, 1))],
        c_symptoms[1 + (i % array_length(c_symptoms, 1))],
        false, 'home_service', 'can_wait', 'completed', v_tech, c_tag,
        7.0731, 125.6128,
        now() - ((i * 5) || ' days')::interval
      )
      returning id into v_job;

      -- Twelve 5s and eight 4s -> an average of 4.60, not a flat 5.00.
      v_stars := case when i <= 12 then 5 else 4 end;

      -- BEFORE the review. See the header for why.
      insert into public.job_outcomes (
        job_id, technician_id, diagnosis_correct, rerouted_mid_job, created_at
      ) values (
        v_job, v_tech, (i % 7) <> 0, false,
        now() - ((i * 5) || ' days')::interval + interval '1 hour'
      );

      insert into public.job_reviews (
        job_id, technician_id, reviewer_id, stars, comment, created_at
      ) values (
        v_job, v_tech, v_client, v_stars,
        case when v_stars = 5
             then 'Fast, tidy work and explained the fix clearly.'
             else 'Good job overall, arrived a little later than agreed.'
        end,
        now() - ((i * 5) || ' days')::interval + interval '2 hours'
      )
      on conflict (job_id, reviewer_id) do nothing;
    end loop;

    -- Recomputed from the rows that actually exist, not assigned.
    update public.technicians t
    set total_jobs = (
      select count(*) from public.jobs j
      where j.assigned_technician_id = t.id and j.status = 'completed'
    )
    where t.id = v_tech;

    v_seeded := v_seeded + 1;
    raise notice 'technician %: seeded % completed jobs + reviews.',
      v_tech, c_jobs;
  end loop;

  raise notice 'seeded % technician(s).', v_seeded;

  -- The same test `recommended_technicians` applies, reported back so the push
  -- output answers "will the row show anything?" without a second round trip.
  select count(*) into d_techs_ok
  from public.technicians t
  join public.profiles p on p.id = t.id
  left join public.technician_review_stats s on s.technician_id = t.id
  where t.is_verified = true
    and p.registration_status = 'active'
    and coalesce(t.total_jobs, 0) >= 20
    and s.average_stars >= 4.0;

  raise notice 'WOULD NOW BE RECOMMENDED: % technician(s).', d_techs_ok;
  raise notice '--------------------------------------------------------';
end $$;

-- ---------------------------------------------------------------------------
-- CLEANUP - removes everything this migration wrote, and nothing else
-- ---------------------------------------------------------------------------
--
-- `job_reviews.job_id` and `job_outcomes.job_id` both reference `jobs`, so
-- deleting the tagged jobs takes their reviews and outcomes with them. Then
-- recompute the counter from what survives.
--
--   delete from public.jobs
--   where description = '[DEMO SEED] Backfilled history for the recommended row.';
--
--   update public.technicians t
--   set total_jobs = (
--     select count(*) from public.jobs j
--     where j.assigned_technician_id = t.id and j.status = 'completed'
--   );
