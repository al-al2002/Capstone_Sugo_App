-- SUGO: name the other person on a job, let technicians rate clients, and give
--       the admin console a jobs view and analytics
--
-- Five pieces, and the audience of each is the thing to get right:
--
--   1. client_reviews        a technician's rating of a client        own rows
--   2. job_parties           who is on each of MY jobs                 authenticated
--   3. client_profile()      a client's public profile                 authenticated
--   4. admin_jobs            every job, with both names                service_role ONLY
--   5. admin_analytics()     platform figures for the dashboard        service_role ONLY
--
-- Items 4 and 5 read every job and every account on the platform. They are
-- revoked from anon and authenticated explicitly - the same posture as
-- `admin_verification_queue` in 20260907000006 - because PostgREST exposes
-- every view in `public`, and a view readable by `authenticated` would hand
-- the whole job history to any signed-in user.

-- ===========================================================================
-- 1. Technicians rate clients
-- ===========================================================================
--
-- Reviews ran one way. A client could rate a technician; a technician had no
-- say about a client who cancelled at the door, was abusive, or never paid.
-- On a two-sided marketplace that asymmetry is a safety problem as well as a
-- fairness one: a technician deciding whether to accept a job has no signal
-- at all about who they are about to visit.
--
-- It mirrors `job_reviews` deliberately - one rating per job, whole stars,
-- optional comment, only after the work is completed - so the two directions
-- behave identically and there is one mental model, not two.

create table if not exists public.client_reviews (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  technician_id uuid not null references public.profiles(id) on delete cascade,

  stars integer not null check (stars between 1 and 5),
  comment text check (comment is null or length(comment) <= 1000),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One rating per job from its technician. Editing is an UPDATE, never a
  -- second row.
  unique (job_id, technician_id)
);

comment on table public.client_reviews is
  'A technician''s rating of the client on a completed job. The mirror of '
  'job_reviews. Publicly readable only through client_profile().';

create index if not exists idx_client_reviews_client
  on public.client_reviews (client_id, created_at desc);

alter table public.client_reviews enable row level security;

-- Direct reads are limited to the two people on the rating. Everyone else -
-- including another technician vetting this client - sees it through
-- `client_profile()`, which returns a deliberate subset.
drop policy if exists "client_reviews_select_parties" on public.client_reviews;
create policy "client_reviews_select_parties"
  on public.client_reviews for select to authenticated
  using (client_id = auth.uid() or technician_id = auth.uid());

-- The same three facts `job_reviews_insert_own` checks, from the other side:
-- the caller is the assigned technician, the named client really is the
-- job's client, and the job is finished. The client_id term is what stops a
-- technician attaching a bad rating to somebody who was never their client.
drop policy if exists "client_reviews_insert_technician" on public.client_reviews;
create policy "client_reviews_insert_technician"
  on public.client_reviews for insert to authenticated
  with check (
    technician_id = auth.uid()
    and exists (
      select 1 from public.jobs j
      where j.id = job_id
        and j.assigned_technician_id = auth.uid()
        and j.client_id = client_reviews.client_id
        and j.status = 'completed'
    )
  );

drop policy if exists "client_reviews_update_own" on public.client_reviews;
create policy "client_reviews_update_own"
  on public.client_reviews for update to authenticated
  using (technician_id = auth.uid());

drop policy if exists "client_reviews_delete_own" on public.client_reviews;
create policy "client_reviews_delete_own"
  on public.client_reviews for delete to authenticated
  using (technician_id = auth.uid());

-- The row policy says *which* row; this says *which columns*. Without it the
-- update policy would let a technician move their rating onto a different job
-- or a different client after the fact.
create or replace function public.guard_client_review_update()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  if new.job_id is distinct from old.job_id
     or new.client_id is distinct from old.client_id
     or new.technician_id is distinct from old.technician_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Only the stars and the comment of a rating can be changed';
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists client_reviews_guard_update on public.client_reviews;
create trigger client_reviews_guard_update
  before update on public.client_reviews
  for each row execute function public.guard_client_review_update();

revoke all on table public.client_reviews from anon;

-- ===========================================================================
-- 2. Who is on each of my jobs
-- ===========================================================================
--
-- The bookings list printed "Technician assigned" and "Client assigned"
-- because a `jobs` row carries ids, and `profiles` is readable only by its
-- owner - so neither side could put a name to the other. This resolves both
-- through `profile_display()`, which already returns exactly the public
-- subset (id, name, avatar) for the chat list.
--
-- The technician is `assigned_technician_id` when there is one, and otherwise
-- whoever the client has *requested* (an `offered` match) - so a client
-- waiting on an answer sees who they are waiting for, which is the moment the
-- name matters most.
--
-- `my_rating` is the caller's own verdict on the other party for this job:
-- the stars a client gave the technician, or the stars a technician gave the
-- client. It lets a list show a real rating instead of a grey "Rate" prompt,
-- in one request rather than one per row.

create or replace view public.job_parties as
select
  j.id                                           as job_id,
  j.client_id,
  public.profile_display(j.client_id)            as client,
  coalesce(j.assigned_technician_id, pick.technician_id)
                                                 as technician_id,
  public.profile_display(
    coalesce(j.assigned_technician_id, pick.technician_id)
  )                                              as technician,
  (j.assigned_technician_id is null and pick.technician_id is not null)
                                                 as technician_is_request,
  case
    when j.client_id = auth.uid() then (
      select r.stars from public.job_reviews r
      where r.job_id = j.id and r.reviewer_id = auth.uid()
      limit 1
    )
    else (
      select c.stars from public.client_reviews c
      where c.job_id = j.id and c.technician_id = auth.uid()
      limit 1
    )
  end                                            as my_rating
from public.jobs j
left join lateral (
  select m.technician_id
  from public.job_matches m
  where m.job_id = j.id
    and m.status in ('offered', 'accepted')
  -- An accepted match outranks an outstanding request if both ever exist.
  order by (m.status = 'accepted') desc, m.created_at desc
  limit 1
) pick on true
where j.client_id = auth.uid()
   or j.assigned_technician_id = auth.uid();

comment on view public.job_parties is
  'For each job the caller is on: both parties'' public display, whether the '
  'technician is only requested so far, and the caller''s own rating.';

-- Invoker, so the `jobs`, `job_matches` and review policies decide the rows -
-- a definer view here would return every job on the platform.
alter view public.job_parties set (security_invoker = on);

revoke all on table public.job_parties from anon;
grant select on public.job_parties to authenticated;

-- ===========================================================================
-- 3. A client's public profile
-- ===========================================================================
--
-- Technicians could view nothing about a client, and in Community a client's
-- name led nowhere. This returns what a technician reasonably needs before
-- accepting a job, and nothing a client would not expect to be public:
--
--   published   name, picture, member since, whether their ID was verified,
--               job counts, the rating technicians gave them and those
--               reviews, how many community questions they have asked
--   withheld    phone, email, address, every job's location, photos and
--               free-text description
--
-- Job counts are aggregates. Individual reviews name the device and symptom of
-- the job, as technician reviews do since 20260921000009 - the technician who
-- wrote the review chose to speak about that job publicly.

create or replace function public.client_profile(
  p_client_id uuid,
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
    'id',             p.id,
    'full_name',      p.full_name,
    'avatar_url',     p.avatar_url,
    'member_since',   p.created_at,
    'id_verified',    exists (
      select 1 from public.identity_verifications iv
      where iv.user_id = p.id and iv.status = 'approved'
    ),

    'jobs_posted',    (select count(*) from public.jobs j where j.client_id = p.id),
    'jobs_completed', (select count(*) from public.jobs j
                       where j.client_id = p.id and j.status = 'completed'),
    'jobs_cancelled', (select count(*) from public.jobs j
                       where j.client_id = p.id and j.status = 'cancelled'),

    'rating',         coalesce(st.average_stars, 0),
    'rating_count',   coalesce(st.review_count, 0),
    'star_breakdown', jsonb_build_object(
      '5', coalesce(st.star_5, 0), '4', coalesce(st.star_4, 0),
      '3', coalesce(st.star_3, 0), '2', coalesce(st.star_2, 0),
      '1', coalesce(st.star_1, 0)
    ),

    'community_questions', (
      select count(*) from public.community_posts cp where cp.author_id = p.id
    ),

    'reviews', coalesce(rev.items, '[]'::jsonb)
  )
  into v_result
  from public.profiles p
  left join lateral (
    select
      count(*)::integer                               as review_count,
      round(avg(c.stars)::numeric, 2)                 as average_stars,
      count(*) filter (where c.stars = 5)::integer    as star_5,
      count(*) filter (where c.stars = 4)::integer    as star_4,
      count(*) filter (where c.stars = 3)::integer    as star_3,
      count(*) filter (where c.stars = 2)::integer    as star_2,
      count(*) filter (where c.stars = 1)::integer    as star_1
    from public.client_reviews c
    where c.client_id = p.id
  ) st on true
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id',               q.id,
        'stars',            q.stars,
        'comment',          q.comment,
        'created_at',       q.created_at,
        'reviewer_name',    q.reviewer->>'full_name',
        'reviewer_avatar',  q.reviewer->>'avatar_url',
        'job_device_type',  q.device_type,
        'job_brand',        q.brand,
        'job_symptom',      q.problem_symptom,
        'job_service_path', q.service_path
      )
      order by q.created_at desc
    ) as items
    from (
      select c.id, c.stars, c.comment, c.created_at,
             public.profile_display(c.technician_id) as reviewer,
             j.device_type, j.brand, j.problem_symptom, j.service_path
      from public.client_reviews c
      left join public.jobs j on j.id = c.job_id
      where c.client_id = p.id
      order by c.created_at desc
      limit v_limit
    ) q
  ) rev on true
  where p.id = p_client_id
    and p.role = 'client';

  if v_result is null then
    raise exception 'Client not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

comment on function public.client_profile(uuid, integer) is
  'A client''s public profile: name, picture, ID-verified flag, job counts, '
  'the ratings technicians gave them. Never phone, email or any location.';

revoke all on function public.client_profile(uuid, integer) from public, anon;
grant execute on function public.client_profile(uuid, integer) to authenticated;

-- ===========================================================================
-- 4. Every job, for the admin console
-- ===========================================================================
--
-- One row per job with both people named, where the work has got to, and how
-- it was rated each way. The console renders progress from `status` and
-- `tracking_stage` rather than from a number computed here, so the steps it
-- shows can be relabelled without a migration.
--
-- Joins `auth.users` for the client's email, which is only possible as the
-- view owner - one more reason this can never be granted beyond service_role.

create or replace view public.admin_jobs as
select
  j.id,
  j.created_at,
  j.status,
  j.device_type,
  j.brand,
  j.problem_symptom,
  j.service_path,
  j.urgency,
  j.budget_min,
  j.budget_max,
  j.preferred_schedule,
  j.address_text,

  j.client_id,
  pc.full_name                          as client_name,
  pc.avatar_url                         as client_avatar,
  uc.email                              as client_email,

  coalesce(j.assigned_technician_id, pick.technician_id)
                                        as technician_id,
  pt.full_name                          as technician_name,
  pt.avatar_url                         as technician_avatar,
  (j.assigned_technician_id is null and pick.technician_id is not null)
                                        as awaiting_technician,
  pick.created_at                       as requested_at,

  tr.stage                              as tracking_stage,
  tr.updated_at                         as tracking_updated_at,

  o.created_at                          as completed_at,
  o.diagnosis_correct,

  r.stars                               as client_rating_of_technician,
  r.comment                             as client_review_comment,
  cr.stars                              as technician_rating_of_client,

  (select count(*) from public.job_matches m where m.job_id = j.id)
                                        as match_count
from public.jobs j
join public.profiles pc on pc.id = j.client_id
left join auth.users uc on uc.id = j.client_id
left join lateral (
  select m.technician_id, m.created_at
  from public.job_matches m
  where m.job_id = j.id and m.status in ('offered', 'accepted')
  order by (m.status = 'accepted') desc, m.created_at desc
  limit 1
) pick on true
left join public.profiles pt
  on pt.id = coalesce(j.assigned_technician_id, pick.technician_id)
left join public.job_tracking tr on tr.job_id = j.id
left join lateral (
  select o.created_at, o.diagnosis_correct
  from public.job_outcomes o
  where o.job_id = j.id
  order by o.created_at desc
  limit 1
) o on true
left join lateral (
  select jr.stars, jr.comment from public.job_reviews jr
  where jr.job_id = j.id
  order by jr.created_at desc
  limit 1
) r on true
left join lateral (
  select c.stars from public.client_reviews c
  where c.job_id = j.id
  order by c.created_at desc
  limit 1
) cr on true;

comment on view public.admin_jobs is
  'Admin console: every job with client and technician named, tracking stage, '
  'completion and both ratings. service_role only.';

revoke all on table public.admin_jobs from anon, authenticated;
grant select on public.admin_jobs to service_role;

-- ===========================================================================
-- 5. Analytics for the admin dashboard
-- ===========================================================================
--
-- One jsonb document, one round trip. The dashboard would otherwise need a
-- dozen PostgREST calls to draw one page - the same reason
-- `admin_dashboard_stats` is a single view.

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
      'available_now',  (select count(*) from technicians where is_verified and is_available)
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
