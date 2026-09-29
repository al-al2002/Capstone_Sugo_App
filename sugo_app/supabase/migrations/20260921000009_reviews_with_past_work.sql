-- SUGO: show a technician's past work alongside their reviews
--
-- A client deciding whether to book somebody wants two things from a profile:
-- *what have they fixed*, and *how did it go*. The profile answered neither
-- properly. A review said "5 stars - fast, tidy work" with no indication of
-- what the work was, so a glowing review of an aircon job read exactly the same
-- as one for the laptop repair the client actually needs.
--
-- This adds two things to `technician_profile()`, and the matching fields to
-- `technician_reviews()` so later pages are not poorer than the first:
--
--   1. Per review: the job it was for - device, brand, symptom, service path.
--   2. Per technician: a count of completed jobs by device type, including
--      jobs that were never reviewed.
--
-- ---------------------------------------------------------------------------
-- WHAT IS EXPOSED, AND WHAT DELIBERATELY IS NOT
-- ---------------------------------------------------------------------------
--
-- A job row belongs to the client who posted it, and most of it is theirs to
-- keep private. So only the fields that describe *the repair* are published:
--
--   published   device_type, brand, problem_symptom, service_path
--   withheld    latitude/longitude, address_text, photo_urls, description,
--               budget, schedule - anything that locates, pictures or
--               describes the client or their home
--
-- `problem_symptom` is safe because it is a catalog key chosen from a fixed
-- list ("laptop_screen_broken"), not text the client typed. `description` IS
-- free text - "the one in my daughter's room, gate code 4471" is exactly what
-- people write there - so it never leaves the jobs table.
--
-- And the per-job detail is only attached to jobs that carry a review. The
-- reviewer has already chosen to speak publicly about that job, under their
-- name, so naming the device alongside it adds nothing they have not already
-- disclosed. Jobs with no review contribute only to an anonymous count.

-- ---------------------------------------------------------------------------
-- 1. The profile
-- ---------------------------------------------------------------------------
--
-- Returns jsonb, so `create or replace` keeps the existing grants. Everything
-- below is the 20260916000008 definition unchanged, except the `rev` lateral
-- (now joins `jobs`) and the new `work` lateral.

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

    -- NEW. Completed work by device, e.g. [{laptop, 8}, {phone, 6}].
    'work_history',    coalesce(work.items, '[]'::jsonb),

    'contact_unlocked', booked.has_booking,
    'phone', case when booked.has_booking then p.phone else null end,
    'shop_name', case when booked.has_booking then t.shop_name else null end,
    'shop_latitude', case
      when booked.has_booking
      then coalesce(t.shop_latitude, t.base_latitude::double precision)
      else null
    end,
    'shop_longitude', case
      when booked.has_booking
      then coalesce(t.shop_longitude, t.base_longitude::double precision)
      else null
    end
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
      and f.photo_url is not null
  ) port on true

  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id',               q.id,
        'stars',            q.stars,
        'comment',          q.comment,
        'created_at',       q.created_at,
        'reviewer_name',    q.reviewer_name,
        'reviewer_avatar',  q.reviewer_avatar,
        -- NEW: the repair this review is about. See the header for why these
        -- four fields and no others.
        'job_device_type',  q.job_device_type,
        'job_brand',        q.job_brand,
        'job_symptom',      q.job_symptom,
        'job_service_path', q.job_service_path
      )
      order by q.created_at desc
    ) as items
    from (
      select r.id, r.stars, r.comment, r.created_at,
             rp.full_name   as reviewer_name,
             rp.avatar_url  as reviewer_avatar,
             j.device_type     as job_device_type,
             j.brand           as job_brand,
             j.problem_symptom as job_symptom,
             j.service_path    as job_service_path
      from public.job_reviews r
      join public.profiles rp on rp.id = r.reviewer_id
      -- LEFT, so a review whose job was somehow removed still shows its
      -- stars and words rather than vanishing from the technician's record.
      left join public.jobs j on j.id = r.job_id
      where r.technician_id = t.id
      order by r.created_at desc
      limit v_limit
    ) q
  ) rev on true

  -- NEW. Every completed job counts here, reviewed or not - that is the
  -- difference between "past work" and "reviews". Aggregate only: no ids, no
  -- dates, nothing that identifies a particular client.
  left join lateral (
    select jsonb_agg(
      jsonb_build_object('device_type', w.device_type, 'jobs', w.jobs)
      order by w.jobs desc, w.device_type
    ) as items
    from (
      select j.device_type, count(*)::integer as jobs
      from public.jobs j
      where j.assigned_technician_id = t.id
        and j.status = 'completed'
      group by j.device_type
    ) w
  ) work on true

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
    and t.is_verified = true
    and p.registration_status = 'active';

  if v_result is null then
    raise exception 'Technician not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. The paged reviews
-- ---------------------------------------------------------------------------
--
-- Returns a TABLE, and adding columns to a table return type is not something
-- `create or replace` can do - it must be dropped and recreated. Dropping a
-- function drops its grants with it, so they are re-applied at the end, in
-- the same revoke-then-grant order as 20260916000001.
--
-- Without this, the first page of reviews would show the repair and every page
-- after it would not - a profile that gets less informative as you scroll.

drop function if exists public.technician_reviews(uuid, timestamptz, integer);

create function public.technician_reviews(
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
  reviewer_avatar text,
  job_device_type text,
  job_brand text,
  job_symptom text,
  job_service_path text
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
         rp.full_name, rp.avatar_url,
         j.device_type, j.brand, j.problem_symptom, j.service_path
  from public.job_reviews r
  join public.profiles rp on rp.id = r.reviewer_id
  join public.technicians t on t.id = r.technician_id
  join public.profiles tp on tp.id = t.id
  left join public.jobs j on j.id = r.job_id
  where r.technician_id = p_technician_id
    and t.is_verified = true
    and tp.registration_status = 'active'
    and (p_before is null or r.created_at < p_before)
  order by r.created_at desc
  limit v_limit;
end;
$function$;

comment on function public.technician_reviews(uuid, timestamptz, integer) is
  'Keyset-paged reviews for one technician, newest first, each with the '
  'repair it was about (device, brand, symptom, service path - never the '
  'client''s location, photos or free-text description). Pass the last row''s '
  'created_at as p_before for the next page.';

revoke all on function public.technician_reviews(uuid, timestamptz, integer)
  from public, anon;
grant execute on function public.technician_reviews(uuid, timestamptz, integer)
  to authenticated;
