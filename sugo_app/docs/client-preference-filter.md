# Client preference pre-filter

Added 2026-11-15. While posting a job, a client can set **minimum
requirements** for the technician. A technician who fails one is **removed**
before RB-CARS scores anyone. They are not ranked lower. Every requirement is
optional, and a job that sets none is matched exactly as before.

## Where it sits

```
1. Stage 1 hard gates      verified, identity approved, not already declined, within 50 km
2. Client preferences      ← this feature: remove whoever fails a requirement the client set
3. Context + Stage 1       rules re-weight suitability by the job's situation
4. Stage 2                 acceptance likelihood
5. Stage 3 + Top 3         recommendation score, ranking, reasons
```

The client chooses **thresholds from fixed options**, never weights or
percentages. How much distance counts against rating is still the engine's
decision, re-weighted by context. The client says what they won't accept, and
RB-CARS decides who is best among the rest.

## The five preferences

| Preference | Options | Rule (technician is kept when...) | Real data used |
|---|---|---|---|
| Specialization | Computer/Laptop · PC Building · Phone/Tablet · Network & Device Setup · Appliance Service | they declared a specialisation on a matching device | `technician_specializations.device_type`, plus the legacy `technicians.specialization` array |
| Maximum distance | 3 · 5 · 10 km | base-to-pin distance ≤ the limit | `base_latitude/longitude` (falls back to live position, as scoring does) |
| Minimum rating | 3.0+ · 4.0+ · 4.5+ | `rating` ≥ the minimum | `technicians.rating` |
| Availability *(no longer asked, see below)* | Available now · Pick a date | **now:** not on time off today and not on another `confirmed`/`in_progress` job. **date:** no time off covering that day | `away_until`, `jobs`, `technician_time_off` |
| Trust badge | ID verified < Skill verified < Community Trusted | their rung for this job ≥ the chosen rung | `technicians.badge` + verified specializations, see below |

### 2026-11-17: Availability removed from the app

At the user's request, step 2 ("Your technician") no longer asks about
availability, so the client now sets four preferences. Availability is
already covered without asking: a technician on time off cannot be booked
(`job-response`), and Stage 2 scores workload, so a busy technician ranks
lower. The "date" option also promised a day that matching, which runs
straight after posting, was not about.

Only the question was removed:

- **No migration and no redeploy.** `pref_availability` and
  `pref_available_on` stay on `jobs`, and the engine still applies them.
  A new job writes null there, which filters nobody.
- **Older jobs** that set availability keep it for re-matching and the
  decline cascade, so they match the way they were posted.
- **"Edit post" drops it** (`JobPostingProvider._prefill`), because the
  client could no longer see or clear it there. The edit then saves null.

The same day, the app stopped showing the name "RB-CARS" to users and says
"SUGO" instead (for example, "Skip this and SUGO ranks everyone nearby").
RB-CARS is still the algorithm's name in the code, the docs and the
manuscript.

Specialization mapping: Computer/Laptop → laptop, desktop · PC Building →
desktop · Phone/Tablet → smartphone, tablet · Network & Device Setup → router,
cctv, printer · Appliance Service → aircon, refrigerator, washing machine,
television, microwave. The app only offers the options that fit the device
picked on step 1, so a combination that could never match is never offered.

### The trust ladder

Since the [Progressive Trust Badge](trust-badge.md) (also 2026-11-15), this
preference reads the same badge the profile shows and RB-CARS scores. The
first version of this feature topped the ladder with "Certified Pro", because
no track-record data existed yet. Community Trusted replaced it the same day,
and any saved `certified_pro` preference was carried over.

A technician's rung **for this job** is their stored badge, capped at ID
verified unless one of their verified specializations covers this job's
device:

1. **ID verified**: identity and email confirmed.
2. **Skill verified**: proven on a device this job needs, by a passed
   assessment or an approved certificate.
3. **Community Trusted**: the stored badge is Community Trusted **and** they
   are skill verified for this job's device.

Rung 3 requires rung 2, so the comparison stays properly ordered (`>=`). A
Community Trusted technician who has never been proven on this device doesn't
outrank a skill-verified one. This also covers the badge acceptance criterion
*"Skill Verified only for Phone/Tablet is not matched for PC Building jobs"*:
on a PC Building job they hold rung 1, so a "Skill verified" requirement
excludes them.

## Storage: why columns on `jobs`

Migration `20261115000001_job_technician_preferences.sql` adds six nullable
columns (`pref_specialization`, `pref_max_distance_km`, `pref_min_rating`,
`pref_availability`, `pref_available_on`, `pref_min_trust`). The RB-CARS schema
is frozen, and this change was approved by the user.

- **On the job, not in the request.** Matching runs from four places: posting,
  "search again", community → service, and the decline cascade. A preference
  carried only in the request would be forgotten by three of them.
- **Typed columns with CHECK constraints, not jsonb.** The database itself
  refuses a 4.2 rating or a 7 km radius, whoever writes it.
- **No RLS change, no new table.** Inserts use the existing
  `jobs_client_insert_own`. Edits go through `job-response`, whose whitelist
  gained the six names.

## When nobody qualifies

The engine returns `no_match_relax_preferences: true` and a
`preference_filter` block, which includes a `relax_hints` count for each
preference: how many technicians removing only that one would bring back.
The message names the most useful one, e.g. *"Removing “Within 3 km” would
bring back 2 technicians."*

The review screen shows **"No technician matches your preferences"** with one
chip per preference. Tapping a chip removes that preference, saves it on the
job and runs RB-CARS again. "Clear all and search again" removes every
preference. The flag is only set when the preferences caused the empty
result. An empty pool for any other reason (nobody within 50 km, everyone
already declined) shows the ordinary empty state, because relaxing wouldn't
help.

## Files

| Layer | File |
|---|---|
| Migration | `supabase/migrations/20261115000001_job_technician_preferences.sql` |
| Filter (pure) | `supabase/functions/match-technician/scoring/preferences.ts` |
| Filter tests | `scoring/preferences.test.ts` (`node --experimental-strip-types preferences.test.ts`) |
| Pipeline | `scoring/engine.ts` (`loadAvailabilityFacts`, the gate block before scoring) |
| Edits | `job-response/index.ts` (`EDITABLE_JOB_FIELDS`, cascade flag) |
| Model | `lib/features/rb_cars/models/technician_preferences.dart` |
| Step 2 | `lib/features/rb_cars/screens/technician_preferences_screen.dart` |
| Controls | `lib/features/rb_cars/widgets/preference_controls.dart` |
| Way out | `lib/features/rb_cars/widgets/relax_preferences_panel.dart` |

## Deploying, in this order

1. `supabase db push`, which applies the migration.
2. `supabase functions deploy match-technician job-response`. Both bundle the
   engine, because the cascade in `job-response` calls it.
3. Ship the app.

A post with no preferences sends no `pref_*` columns, so an app build that
reaches users before step 1 still posts normally. Only setting a preference
needs the migration.

## Known limitations

- **Distance is straight-line**, like the rest of RB-CARS, not road distance.
- **"Available now" trusts the job statuses.** A technician who forgot to
  start or complete a job in the app reads as free or busy accordingly.
- **A failed availability lookup applies the preference without that fact**
  (for "now", time off is still checked) rather than removing everyone. It is
  logged, and `job-response` re-checks time off before any booking.
- **Unrated technicians fail any minimum rating.** This is honest (there is no
  rating to compare), and the app says so beside the field. It does
  disadvantage new technicians when a client sets one.
