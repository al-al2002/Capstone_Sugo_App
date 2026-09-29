-- SUGO: demo technicians for RB-CARS
--
-- Run this in the Supabase SQL Editor AFTER 20260905000001_rb_cars_schema.sql.
-- It is a seed script, not a migration: it is not in supabase/migrations/ and
-- `supabase db push` will not run it.
--
-- ## Why you need it
--
-- `match-technician` only ranks rows in `technicians` where `is_verified` is
-- true. With an empty table every match returns zero results and the review
-- screen shows "No technicians matched yet". That is correct behaviour, but it
-- makes for a poor defence demo.
--
-- ## The constraint to understand
--
-- `technicians.id` references `profiles(id)`, which references
-- `auth.users(id)`. You therefore cannot invent technician uuids - each one
-- must be a real account. So: sign up five accounts through the SUGO app (the
-- trigger in the profiles migration creates their `profiles` rows), then run
-- this script. It promotes the five oldest profiles that are not already
-- technicians.
--
-- Coordinates are scattered around Davao City so distance and proximity
-- scoring produce visibly different results.

do $$
declare
  ids uuid[];
begin
  select array_agg(p.id order by p.created_at)
  into ids
  from public.profiles p
  where not exists (
    select 1 from public.technicians t where t.id = p.id
  );

  if ids is null or array_length(ids, 1) < 1 then
    raise notice 'No un-promoted profiles found. Sign up some accounts first.';
    return;
  end if;

  raise notice 'Found % profiles available to promote.', array_length(ids, 1);

  -- 1. Elite laptop and phone specialist, close in, busy.
  if array_length(ids, 1) >= 1 then
    insert into public.technicians (
      id, skill_tags, tier, specialization, is_verified, is_available, badge,
      rating, total_jobs, current_workload, latitude, longitude
    ) values (
      ids[1],
      array[
        'laptop_screen_broken','laptop_overheating','laptop_no_os',
        'phone_screen_cracked','screen_replacement','board_repair'
      ],
      'elite',
      array['laptop','phone'],
      true, true,
      'Elite Repair Pro',
      4.90, 152, 1,
      7.0731, 125.6128           -- Davao city centre
    );
  end if;

  -- 2. Pro appliance technician, north, free today.
  if array_length(ids, 1) >= 2 then
    insert into public.technicians (
      id, skill_tags, tier, specialization, is_verified, is_available, badge,
      rating, total_jobs, current_workload, latitude, longitude
    ) values (
      ids[2],
      array[
        'appliance_not_cooling','appliance_no_power','appliance_water_leak',
        'aircon_service','refrigeration'
      ],
      'pro',
      array['appliance'],
      true, true,
      'Aircon Specialist',
      4.70, 88, 0,
      7.1000, 125.6200           -- Buhangin side
    );
  end if;

  -- 3. Standard network technician, south, moderate load.
  if array_length(ids, 1) >= 3 then
    insert into public.technicians (
      id, skill_tags, tier, specialization, is_verified, is_available, badge,
      rating, total_jobs, current_workload, latitude, longitude
    ) values (
      ids[3],
      array[
        'network_no_internet','network_weak_signal','network_cctv_offline',
        'cabling','router_config'
      ],
      'standard',
      array['network'],
      true, true,
      null,
      4.30, 41, 2,
      7.0500, 125.5900           -- Matina side
    );
  end if;

  -- 4. COLD START: verified, zero jobs, no rating. This is the row that
  --    demonstrates the cold-start boost in Stage 1 - it should still reach a
  --    Top 3 despite having no history at all.
  if array_length(ids, 1) >= 4 then
    insert into public.technicians (
      id, skill_tags, tier, specialization, is_verified, is_available, badge,
      rating, total_jobs, current_workload, latitude, longitude
    ) values (
      ids[4],
      array['laptop_slow_or_freezing','laptop_no_os','phone_software_stuck'],
      'standard',
      array['laptop','phone'],
      true, true,
      'New on SUGO',
      0, 0, 0,
      7.0800, 125.6100
    );
  end if;

  -- 5. UNVERIFIED: should never appear in a match. Proof the pool filter and
  --    the verification gate are doing something.
  if array_length(ids, 1) >= 5 then
    insert into public.technicians (
      id, skill_tags, tier, specialization, is_verified, is_available, badge,
      rating, total_jobs, current_workload, latitude, longitude
    ) values (
      ids[5],
      array['laptop_screen_broken','phone_screen_cracked'],
      'pro',
      array['laptop','phone'],
      false, false,
      null,
      4.80, 60, 0,
      7.0750, 125.6150
    );
  end if;

  -- The router reads profiles.role, so promoting someone to technician means
  -- flipping that too. Without this they would land on the client dashboard
  -- despite having a technicians row.
  update public.profiles
  set role = 'technician'
  where id = any(ids[1:5]);

  raise notice 'Seeded technicians and set profiles.role = technician.';
end $$;

-- Check what landed, including the profile name each row is attached to.
select
  t.id,
  p.full_name,
  t.tier,
  t.specialization,
  t.is_verified,
  t.is_available,
  p.role,
  t.rating,
  t.total_jobs,
  t.current_workload
from public.technicians t
join public.profiles p on p.id = t.id
order by t.is_verified desc, t.rating desc;
