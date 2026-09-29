-- =============================================================================
-- Retire the online/offline switch
-- =============================================================================
--
-- The app no longer has an online/offline toggle. Availability is decided by
-- time off (`technician_time_off`, 20260922000003) alone: a technician is
-- bookable unless today falls inside one of their vacations.
--
-- WHY
--
-- The switch had to be flipped by hand, many times a day. One left off by
-- accident sank a qualified technician to the bottom of every Top 3 - it was
-- the heaviest factor in Stage 2 - and nothing told them. Vacation days are
-- planned once, end by themselves, and answer the question a client actually
-- has: can I book this person?
--
-- WHAT CHANGES HERE
--
--   1. `technicians.is_available` stays - `technicians` is one of the four
--      frozen RB-CARS tables - but is documented as retired. Nothing in the
--      app, the edge functions or the admin console reads it any more; the
--      listing functions still pass it through untouched, and no one uses it.
--      Its current values are left as they are: rewriting data nobody reads
--      would only erase the record of what the switch last said.
--
--   2. The admin dashboard's "technicians online now" figure becomes
--      "technicians on vacation today", in admin_analytics(). The function is
--      otherwise identical to the 20260922000002 version, copied from that
--      file rather than retyped.
-- =============================================================================

comment on column public.technicians.is_available is
  'RETIRED 2026-09-22. The old online/offline switch. Read by nothing: '
  'availability is technician_time_off (see technician_away_until()). '
  'Kept because the RB-CARS tables are frozen.';

create or replace function public.admin_analytics()
returns jsonb
language sql
stable
security definer
set search_path = public
as $function$
  select jsonb_build_object(
    'users', jsonb_build_object(
      'clients',        (select count(*) from profiles where role = 'client'),
      'technicians',    (select count(*) from profiles where role = 'technician'),
      'active',         (select count(*) from profiles where registration_status = 'active'),
      'pending_review', (select count(*) from profiles where registration_status = 'pending_review'),
      'incomplete',     (select count(*) from profiles where registration_status = 'incomplete'),
      'new_7d',         (select count(*) from profiles where created_at > now() - interval '7 days'),
      -- Replaces 'available_now', which counted the retired online switch.
      'on_vacation',    (select count(*) from technicians t
                         where t.is_verified
                           and public.technician_away_until(t.id) is not null)
    ),

    'jobs', jsonb_build_object(
      'total',       (select count(*) from jobs),
      'pending',     (select count(*) from jobs where status = 'pending'),
      'matched',     (select count(*) from jobs where status = 'matched'),
      'confirmed',   (select count(*) from jobs where status = 'confirmed'),
      'in_progress', (select count(*) from jobs where status = 'in_progress'),
      'completed',   (select count(*) from jobs where status = 'completed'),
      'cancelled',   (select count(*) from jobs where status = 'cancelled'),
      'last_7d',     (select count(*) from jobs where created_at > now() - interval '7 days'),
      -- Of the jobs that reached an end state, how many ended well. Counting
      -- open jobs in the denominator would make a busy week look like a
      -- failing one.
      'completion_rate', (
        select case when count(*) = 0 then 0
               else round(100.0 * count(*) filter (where status = 'completed')
                          / count(*), 1) end
        from jobs where status in ('completed', 'cancelled')
      )
    ),

    -- Last 14 days, zero-filled so the chart has no gaps on quiet days.
    'daily', (
      select jsonb_agg(jsonb_build_object(
        'day',       to_char(d.day, 'YYYY-MM-DD'),
        'posted',    (select count(*) from jobs j
                      where j.created_at >= d.day and j.created_at < d.day + interval '1 day'),
        'completed', (select count(*) from job_outcomes o
                      where o.created_at >= d.day and o.created_at < d.day + interval '1 day')
      ) order by d.day)
      from generate_series(
        date_trunc('day', now()) - interval '13 days',
        date_trunc('day', now()),
        interval '1 day'
      ) as d(day)
    ),

    'devices', coalesce((
      select jsonb_agg(jsonb_build_object('device_type', device_type, 'jobs', n)
                       order by n desc)
      from (select device_type, count(*) as n from jobs group by device_type) x
    ), '[]'::jsonb),

    'service_paths', coalesce((
      select jsonb_agg(jsonb_build_object('service_path', service_path, 'jobs', n)
                       order by n desc)
      from (select coalesce(service_path, 'unclassified') as service_path,
                   count(*) as n
            from jobs group by 1) x
    ), '[]'::jsonb),

    'ratings', jsonb_build_object(
      'technician_avg',   (select round(avg(stars)::numeric, 2) from job_reviews),
      'technician_count', (select count(*) from job_reviews),
      'client_avg',       (select round(avg(stars)::numeric, 2) from client_reviews),
      'client_count',     (select count(*) from client_reviews)
    ),

    'top_technicians', coalesce((
      select jsonb_agg(row_to_json(x)::jsonb)
      from (
        select p.full_name as name,
               coalesce(t.total_jobs, 0) as jobs,
               s.average_stars as rating,
               coalesce(s.review_count, 0) as reviews
        from technicians t
        join profiles p on p.id = t.id
        left join technician_review_stats s on s.technician_id = t.id
        where t.is_verified
        order by coalesce(t.total_jobs, 0) desc, s.average_stars desc nulls last
        limit 5
      ) x
    ), '[]'::jsonb),

    -- NEW (20260922000002). The mirror of top_technicians: the clients who
    -- have actually used SUGO to get repairs done. Ranked by completed jobs,
    -- then by jobs posted, then by how technicians rated them - so a client
    -- with many finished repairs ranks above one who posts a lot and cancels.
    -- Clients who have never posted are left out: an empty row is not a
    -- "top" anything.
    'top_clients', coalesce((
      select jsonb_agg(row_to_json(x)::jsonb)
      from (
        select p.full_name as name,
               count(j.id) filter (where j.status = 'completed') as jobs,
               count(j.id) as posted,
               r.average_stars as rating,
               coalesce(r.review_count, 0) as reviews
        from profiles p
        join jobs j on j.client_id = p.id
        left join (
          select client_id,
                 round(avg(stars)::numeric, 2) as average_stars,
                 count(*) as review_count
          from client_reviews
          group by client_id
        ) r on r.client_id = p.id
        where p.role = 'client'
        group by p.id, p.full_name, r.average_stars, r.review_count
        order by jobs desc, posted desc, rating desc nulls last
        limit 5
      ) x
    ), '[]'::jsonb),

    'community', jsonb_build_object(
      'questions', (select count(*) from community_posts),
      'answers',   (select count(*) from community_comments),
      'helpful',   (select count(*) from community_votes)
    ),

    'verifications', jsonb_build_object(
      'pending',  (select count(*) from identity_verifications where status = 'pending'),
      'approved', (select count(*) from identity_verifications where status = 'approved'),
      'rejected', (select count(*) from identity_verifications where status = 'rejected')
    ),

    'generated_at', now()
  );
$function$;

comment on function public.admin_analytics() is
  'Every figure the admin dashboard charts, in one document. service_role only.';

revoke all on function public.admin_analytics() from public, anon, authenticated;
grant execute on function public.admin_analytics() to service_role;
