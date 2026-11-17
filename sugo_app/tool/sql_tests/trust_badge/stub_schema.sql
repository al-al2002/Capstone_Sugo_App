-- Minimal stand-in for the SUGO schema: only the tables, columns, constraints,
-- functions and triggers the two 2026-11-15 migrations touch, copied from the
-- real migrations where behaviour matters (guard, inherit, assessment track).

create role anon;
create role authenticated;
create role service_role;

create schema auth;
create table auth.users (id uuid primary key, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table public.profiles (
  id uuid primary key,
  role text,
  registration_status text default 'active',
  full_name text,
  phone text
);

create table public.technicians (
  id uuid primary key references public.profiles(id),
  tier text not null default 'standard',
  is_verified boolean not null default true,
  verification_tier text not null default 'verified',
  badge text,
  rating numeric(3,2) default 0,
  total_jobs integer default 0,
  current_workload integer default 0
);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null,
  assigned_technician_id uuid references public.technicians(id),
  device_type text not null default 'phone',
  brand text,
  problem_symptom text not null default 'x',
  status text not null default 'pending'
);

create table public.job_matches (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id),
  technician_id uuid not null references public.technicians(id),
  rank integer not null default 1,
  status text not null default 'shortlisted'
    check (status in ('shortlisted', 'offered', 'declined', 'accepted'))
);

create table public.job_outcomes (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id),
  technician_id uuid not null references public.technicians(id),
  final_rating numeric(3,2)
);

create table public.job_disputes (
  id              uuid primary key default gen_random_uuid(),
  job_id          uuid not null references public.jobs(id) on delete cascade,
  raised_by       uuid not null references public.profiles(id) on delete cascade,
  raised_by_role  text not null check (raised_by_role in ('client', 'technician')),
  reason          text not null default 'not_fixed',
  details         text not null default 'details details',
  photo_paths     text[] not null default '{}',
  status          text not null default 'open'
                    check (status in ('open', 'resolved', 'dismissed')),
  resolution_note text,
  resolved_by     uuid references public.profiles(id),
  resolved_at     timestamptz,
  created_at      timestamptz not null default now(),
  constraint job_disputes_decided_consistently check (
    (status = 'open' and resolved_at is null)
    or (status <> 'open' and resolved_at is not null
        and length(trim(coalesce(resolution_note, ''))) > 0)
  )
);

create table public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  status text not null default 'pending'
);

create table public.technician_verification_documents (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,
  doc_type text not null check (doc_type in ('certificate', 'nbi_clearance', 'portfolio')),
  file_url text not null default 'x',
  caption text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_notes text,
  reviewed_by uuid,
  uploaded_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create function public.assessment_track(p_device_type text) returns text
language sql immutable as $function$
  select case p_device_type
    when 'laptop' then 'computer_repair' when 'desktop' then 'computer_repair'
    when 'smartphone' then 'mobile_repair' when 'tablet' then 'mobile_repair'
    when 'printer' then 'printer_repair' when 'aircon' then 'refrigeration'
    when 'refrigerator' then 'refrigeration' when 'washing_machine' then 'laundry_appliance'
    when 'television' then 'home_electronics' when 'microwave' then 'home_electronics'
    else p_device_type end;
$function$;

create function public.assessment_skill_level(p_score numeric) returns text
language sql immutable as $$
  select case when p_score >= 90 then 'expert' when p_score >= 80 then 'intermediate'
              when p_score >= 70 then 'beginner' end
$$;

create function public.assessment_retake_cooldown() returns interval
language sql immutable as $$ select interval '7 days' $$;

create table public.technician_specializations (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.technicians(id) on delete cascade,
  category text not null default 'it_device',
  device_type text not null,
  brand text not null default 'Others',
  skill_level text check (skill_level in ('beginner', 'intermediate', 'expert')),
  verified boolean not null default false,
  track text,
  created_at timestamptz not null default now()
);

create function public.set_track() returns trigger language plpgsql as $$
begin new.track := public.assessment_track(new.device_type); return new; end $$;
create trigger technician_specializations_set_track before insert or update of device_type
  on public.technician_specializations for each row execute function public.set_track();

create table public.technician_assessment_results (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null,
  specialization_id uuid,
  track text not null,
  score numeric not null,
  passed boolean not null,
  attempt_number integer not null,
  taken_at timestamptz not null default now()
);

-- Original (pre-20261115000002) inherit trigger, so the migration's
-- replacement is what gets tested.
create function public.inherit_track_verification() returns trigger
language plpgsql security definer set search_path = public as $function$
declare v_level text;
begin
  select public.assessment_skill_level(r.score) into v_level
  from public.technician_assessment_results r
  where r.technician_id = new.technician_id and r.track = new.track and r.passed
  order by r.taken_at desc limit 1;
  if v_level is not null then
    update public.technician_specializations set verified = true, skill_level = v_level where id = new.id;
  end if;
  return null;
end;
$function$;
create trigger technician_specializations_inherit_verification
  after insert on public.technician_specializations
  for each row execute function public.inherit_track_verification();

-- Original guard, replaced by the migration.
create function public.guard_technician_self_update() returns trigger
language plpgsql security definer set search_path = public as $function$
begin
  if auth.uid() is null or auth.uid() <> new.id then return new; end if;
  if new.badge is distinct from old.badge then
    raise exception 'A technician cannot change their own badge';
  end if;
  return new;
end;
$function$;
create trigger guard_technician_self_update before update on public.technicians
  for each row execute function public.guard_technician_self_update();

create function public.review_identity_verification(uuid, boolean, uuid, text)
returns jsonb language sql as $$ select '{}'::jsonb $$;

-- 20261115000001 needs these on jobs; it adds them itself.
