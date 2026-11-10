-- Public, approximate technician location shown on match cards.
-- Exact coordinates remain private and are never exposed to browsing clients.

alter table public.technicians
  add column if not exists barangay text;

comment on column public.technicians.barangay is
  'Public barangay or area label; do not store an exact residential address.';

create or replace view public.matching_candidates as
select
  t.id,
  t.skill_tags,
  t.tier,
  t.specialization,
  t.is_verified,
  t.is_available,
  t.badge,
  t.rating,
  t.total_jobs,
  t.current_workload,
  t.latitude,
  t.longitude,
  t.base_latitude,
  t.base_longitude,
  t.service_radius_km,
  t.verification_tier,
  t.created_at,
  p.full_name,
  p.avatar_url,
  p.phone,
  exists (
    select 1
    from public.identity_verifications iv
    where iv.user_id = t.id
      and iv.status = 'approved'
  ) as identity_approved,
  coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'device_type', s.device_type,
          'brand', s.brand,
          'skill_level', s.skill_level,
          'verified', s.verified,
          'track', s.track
        )
        order by s.created_at
      )
      from public.technician_specializations s
      where s.technician_id = t.id
    ),
    '[]'::jsonb
  ) as specializations,
  public.technician_away_until(t.id) as away_until,
  t.barangay
from public.technicians t
join public.profiles p on p.id = t.id;

revoke all on public.matching_candidates from anon, authenticated;
grant select on public.matching_candidates to service_role;
