-- SUGO: RB-CARS (Context-Aware Recommendation System) schema
--
-- Adds the four tables the matching engine needs on top of the existing
-- `profiles` table created in 20260904000001_create_profiles.sql.
--
--   technicians   - the service-provider side of a profile (1:1 with profiles)
--   jobs          - a repair request posted by a client
--   job_matches   - the Top 3 the engine produced for a job, with its scores
--   job_outcomes  - what actually happened, so scoring can learn from it
--
-- There is deliberately NO `clients` table: a client IS a row in `profiles`.
-- `technicians.id` is the same uuid as `profiles.id`, which is the same uuid as
-- `auth.users.id`. That is what lets every RLS policy below compare a column
-- straight against auth.uid() with no join.

-- `uuid_generate_v4()` lives in the uuid-ossp extension. Supabase ships it in
-- the `extensions` schema; this line makes the migration self-contained so it
-- also runs against a fresh local database.
create schema if not exists extensions;
create extension if not exists "uuid-ossp" with schema extensions;

-- TECHNICIANS (extends profiles — same id, not a new uuid)
create table technicians (
  id uuid primary key references profiles(id) on delete cascade,
  skill_tags text[] not null default '{}',
  tier text not null default 'standard' check (tier in ('standard','pro','elite')),
  specialization text[] not null default '{}',
  is_verified boolean not null default false,
  badge text,
  rating numeric(3,2) default 0,
  total_jobs integer default 0,
  current_workload integer default 0,
  latitude double precision,
  longitude double precision,
  created_at timestamptz default now()
);

-- JOBS / BOOKINGS
create table jobs (
  id uuid primary key default uuid_generate_v4(),
  client_id uuid references profiles(id) not null,
  device_type text not null check (device_type in ('laptop','phone','appliance','network')),
  problem_symptom text not null,
  has_physical_damage boolean not null default false,
  classification_confidence text check (classification_confidence in ('high','low')),
  service_path text check (service_path in ('home_service','pickup','it_community')),
  urgency text not null default 'can_wait' check (urgency in ('need_today','can_wait')),
  latitude double precision,
  longitude double precision,
  budget_min numeric,
  budget_max numeric,
  preferred_schedule timestamptz,
  description text,
  photo_urls text[],
  status text not null default 'pending' check (
    status in ('pending','matched','confirmed','in_progress','completed','cancelled')
  ),
  assigned_technician_id uuid references technicians(id),
  created_at timestamptz default now()
);

-- MATCH RESULTS
create table job_matches (
  id uuid primary key default uuid_generate_v4(),
  job_id uuid references jobs(id) not null,
  technician_id uuid references technicians(id) not null,
  rank integer not null check (rank between 1 and 3),
  suitability_score numeric,
  acceptance_score numeric,
  final_score numeric,
  score_breakdown jsonb,
  status text not null default 'offered' check (status in ('offered','declined','accepted')),
  created_at timestamptz default now()
);

-- JOB OUTCOMES (feedback loop)
create table job_outcomes (
  id uuid primary key default uuid_generate_v4(),
  job_id uuid references jobs(id) not null,
  technician_id uuid references technicians(id) not null,
  diagnosis_correct boolean,
  rerouted_mid_job boolean default false,
  final_rating numeric(3,2),
  created_at timestamptz default now()
);

-- INDEXES
create index idx_jobs_status on jobs(status);
create index idx_jobs_client on jobs(client_id);
create index idx_technicians_verified on technicians(is_verified);
create index idx_job_matches_job on job_matches(job_id);
create index idx_job_outcomes_technician on job_outcomes(technician_id);

-- ROW LEVEL SECURITY
alter table technicians enable row level security;
alter table jobs enable row level security;
alter table job_matches enable row level security;
alter table job_outcomes enable row level security;

create policy "technicians_select_own" on technicians for select using (id = auth.uid());
create policy "technicians_update_own" on technicians for update using (id = auth.uid());

create policy "jobs_client_select_own" on jobs for select using (client_id = auth.uid());
create policy "jobs_client_insert_own" on jobs for insert with check (client_id = auth.uid());
create policy "jobs_technician_select_assigned" on jobs for select using (assigned_technician_id = auth.uid());

create policy "job_matches_client_select" on job_matches for select using (
  job_id in (select id from jobs where client_id = auth.uid())
);
create policy "job_matches_technician_select" on job_matches for select using (technician_id = auth.uid());

create policy "job_outcomes_client_select" on job_outcomes for select using (
  job_id in (select id from jobs where client_id = auth.uid())
);
create policy "job_outcomes_technician_select" on job_outcomes for select using (technician_id = auth.uid());
