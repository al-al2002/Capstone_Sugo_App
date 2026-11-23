-- SUGO: a technician's public profile says how they work. (2026-11-23)
--
-- At the user's request: "view technician profile, show the work on rain or
-- traffic". The client-facing profile (`technician_profile`, a SECURITY
-- DEFINER read past `technicians_select_own`) now also returns:
--
--   offers_home_service   - takes Home Service jobs (20261117000007)
--   offers_shop_repair    - takes Shop Repair jobs (20261117000007)
--   rain_travel           - 'any' | 'not_heavy' | 'never' | null (20261122000001)
--   heavy_traffic_travel  - true | false | null (20261122000001)
--
-- All four are the technician's own answers about how they work, the same
-- facts matching already uses; none of them is contact or location data, so
-- they are shown to every signed-in client, not only after a booking.
--
-- Returns jsonb, so `create or replace` keeps the existing grants. The body
-- is the 20260921000009 definition unchanged (checked against the live
-- function before this was written), plus the four keys marked NEW.

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

    -- NEW (2026-11-23): how they work, for the profile's "How they work".
    'offers_home_service',  coalesce(t.offers_home_service, true),
    'offers_shop_repair',   coalesce(t.offers_shop_repair, true),
    'rain_travel',          t.rain_travel,
    'heavy_traffic_travel', t.heavy_traffic_travel,

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
