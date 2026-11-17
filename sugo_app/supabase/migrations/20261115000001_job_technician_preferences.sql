-- SUGO: client preference pre-filter for RB-CARS (2026-11-15)
--
-- A client may now set MINIMUM requirements for their technician while posting
-- a job: a specialisation, a maximum distance, a minimum rating, an
-- availability window and a minimum trust badge. Each one is a hard gate - a
-- technician who fails it is removed from the candidate pool before Stage 1
-- scores anyone - and each one is optional. Null means "No preference" and
-- applies no filter, so a job that sets nothing is matched exactly as before.
--
-- ## Why columns on `jobs`, and why the user approved it
--
-- The RB-CARS schema is frozen; the user approved this change on 2026-11-15.
-- The preferences have to live on the job, not in the match request, because
-- matching runs from four places: posting, the client's "search again",
-- community -> service conversion, and the decline cascade in `job-response`.
-- A preference carried only in the request would be forgotten by three of
-- them - the cascade could then offer a 3.0-star technician to a client who
-- asked for 4.5+. On the row, every caller of `runMatching()` reads it for
-- free.
--
-- ## Why typed columns rather than one jsonb
--
-- The brief says the inputs are fixed-option thresholds, never free values.
-- A CHECK constraint per column makes the database itself refuse anything
-- else - a 4.2 rating or a 7 km radius cannot be stored, whichever client
-- wrote it. A jsonb blob could only be validated by the app.
--
-- ## What did NOT change
--
-- No new table, no RLS change. The client already inserts their own `jobs`
-- row (`jobs_client_insert_own`), and edits go through `job-response`, whose
-- whitelist gains these six names. The weight tables, the composite score and
-- Stage 2 are untouched; the filter lives in
-- `match-technician/scoring/preferences.ts`.

alter table public.jobs
  -- Must offer this specialisation. Mapped to
  -- `technician_specializations.device_type` values in the engine:
  --   computer      -> laptop, desktop
  --   phone_tablet  -> smartphone, tablet
  --   network_setup -> router, cctv, printer
  --   appliance     -> aircon, refrigerator, washing_machine, television, microwave
  --   pc_building   -> desktop
  add column if not exists pref_specialization text
    check (pref_specialization in (
      'computer', 'phone_tablet', 'network_setup', 'appliance', 'pc_building'
    )),

  -- Straight-line km from the technician's base to the job pin.
  add column if not exists pref_max_distance_km smallint
    check (pref_max_distance_km in (3, 5, 10)),

  -- Minimum `technicians.rating`. A technician with no reviews yet has 0 and
  -- is left out when this is set - the app says so beside the field.
  add column if not exists pref_min_rating numeric(2, 1)
    check (pref_min_rating in (3.0, 4.0, 4.5)),

  -- 'now'     = not on time off today AND not on another unfinished job.
  -- 'on_date' = not on time off on `pref_available_on`.
  add column if not exists pref_availability text
    check (pref_availability in ('now', 'on_date')),

  add column if not exists pref_available_on date,

  -- An ordered ladder, compared with >=, never equality:
  --   id_verified    - identity approved (every matchable technician)
  --   skill_verified - passed the assessment for THIS job's device
  --   certified_pro  - skill verified AND verification_tier = certified_pro
  add column if not exists pref_min_trust text
    check (pref_min_trust in ('id_verified', 'skill_verified', 'certified_pro'));

-- A date exactly when, and only when, the client picked "Pick a date".
-- `is not distinct from` so a null availability with a stray date is refused
-- too; a plain `=` would evaluate to null there, and CHECK lets null through.
alter table public.jobs
  drop constraint if exists jobs_pref_available_on_matches;

alter table public.jobs
  add constraint jobs_pref_available_on_matches check (
    (pref_availability is not distinct from 'on_date') =
    (pref_available_on is not null)
  );

comment on column public.jobs.pref_specialization is
  'Client preference (hard gate): technician must offer this specialisation. Null = no preference.';
comment on column public.jobs.pref_max_distance_km is
  'Client preference (hard gate): technician base within this many km of the job. Null = no preference.';
comment on column public.jobs.pref_min_rating is
  'Client preference (hard gate): technicians.rating at least this. Null = no preference.';
comment on column public.jobs.pref_availability is
  'Client preference (hard gate): now = free today; on_date = no time off on pref_available_on. Null = no preference.';
comment on column public.jobs.pref_available_on is
  'The date for pref_availability = on_date; null otherwise.';
comment on column public.jobs.pref_min_trust is
  'Client preference (hard gate, ordered): id_verified < skill_verified < certified_pro. Null = no preference.';
