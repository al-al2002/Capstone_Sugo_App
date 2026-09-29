-- SUGO: a client collecting their own unit needs to know where the shop is
--
-- `ready_for_collection` (20260916000007) lets a client pick their appliance up
-- from the workshop instead of waiting for a delivery. Then they open the
-- tracking screen and there is nowhere to go: the technician's coordinates are
-- deliberately never sent to a client, so the app can name the technician but
-- not the shop.
--
-- ## Why this is not a hole in that rule
--
-- The rule was never "clients may not know where a technician works". It is
-- "BROWSING must not expose it" - `technician-directory` says so in its header,
-- and returns a `distance_km` instead of a coordinate so a card can say "3.4 km
-- away" without the app holding the address of someone the client has not
-- booked.
--
-- A client who has booked this technician, had their appliance collected, and
-- agreed to come and fetch it is not browsing. They are exactly the person the
-- address is for.
--
-- So this reuses the gate that already exists on the phone number: released
-- only when the caller has a confirmed, in-progress or completed job with that
-- technician. Same predicate, same lateral, one more pair of fields behind it.
-- No new access is granted to anyone who did not already have the phone number.
--
-- ## Why the fallback chain stops at base
--
-- `shop_*` then `base_*`, and NOT the live `latitude`/`longitude`. The first
-- two are places a technician registered and expects clients to come to. The
-- third is wherever their phone last was, which on a working day is somebody
-- else's house - sending a client there would be both wrong and a disclosure
-- about a different job.

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

    'contact_unlocked', booked.has_booking,
    'phone', case when booked.has_booking then p.phone else null end,

    -- Behind the same gate as the phone, and for the same reason. Null for a
    -- browsing client, which is what every card and profile screen already
    -- handles.
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
        'id',              q.id,
        'stars',           q.stars,
        'comment',         q.comment,
        'created_at',      q.created_at,
        'reviewer_name',   q.reviewer_name,
        'reviewer_avatar', q.reviewer_avatar
      )
      order by q.created_at desc
    ) as items
    from (
      select r.id, r.stars, r.comment, r.created_at,
             rp.full_name as reviewer_name,
             rp.avatar_url as reviewer_avatar
      from public.job_reviews r
      join public.profiles rp on rp.id = r.reviewer_id
      where r.technician_id = t.id
      order by r.created_at desc
      limit v_limit
    ) q
  ) rev on true

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

comment on function public.technician_profile(
  uuid, double precision, double precision, integer
) is
  'One technician profile as a single jsonb document: specialisations, '
  'portfolio, star breakdown, total jobs and the first page of reviews. Phone '
  'and workshop location are released only to a client with a real booking.';
