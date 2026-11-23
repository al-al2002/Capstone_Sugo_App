# Technician work types: Home Service, Shop Repair, or both

Added 2026-11-17. At registration a technician says which work they take, and
matching only offers a job to technicians who take its kind of work.

## What changed, for each person

**Technician, registering.** A new step, **Work type**, between Documents and
Location:

| Option | What it says it involves |
| --- | --- |
| **Home Service** - you go to the client | Repair, clean or install at the client's home or office. Bring your own tools and diagnose on the spot. Offered jobs within your travel radius. |
| **Shop Repair** - the unit comes to your shop | Clients drop it off, or you collect it and bring it back. Bench work: board repair, part swaps, data recovery. Needs your shop's location on the map. |

- One or both may be picked; nothing is preselected, so it is a real choice.
- Picking **Shop Repair** opens the shop's name (optional) and a map to pin
  the shop. The step cannot be passed without the pin.
- The **Location** step after it is worded for the choice: "Where do you start
  from?" for Home Service, "Your service area" for Shop Repair only. A
  shop-only technician's service area starts at the shop they just pinned.
- The review step shows the work type and whether the shop is pinned.

**Technician, later.** Profile → "Photo and workshop" has **Work you take**
(two switches). Shop Repair cannot be saved on without the workshop pinned.

**Client.** Nothing new to do. A Home Service job is matched only with
technicians who take Home Service, and a Shop Repair job only with those who
take Shop Repair - the Top 3 and the wider "more technicians" list alike. If
nobody takes that kind of work, the match says so and suggests switching the
service type.

**Admin (sugo-admin).** The work type is shown wherever a technician is
reviewed, read-only like every other account fact (it is the technician's own
choice, not a review decision):

- **Technicians list:** a **Work** column with two pills, Home and Shop, lit
  for the ones they take and struck through for the one they do not.
- **Account page:** "Work type" in the details, and "Shop" (its name, or "Not
  pinned" in amber) when they take Shop Repair.
- **ID review page:** a "Work they take" panel, with whether the shop is
  pinned - a Shop Repair applicant should have one.

`App\Support\WorkType` reads the two flags; `partials/work-type.blade.php`
draws the pills. The controllers read `technicians` directly on the service
role (one query for the whole list, keyed by id), so no view changed.

## The map (registration and address editing)

`LocationPinStep` now finds the user on its own: with nothing pinned it asks
for the current location as soon as it opens, and the pin and map land there.
If that fails (permission declined, GPS off, no fix indoors), nothing is
shown as an error - search ("Search for an address or landmark") and "Use my
current location" are right there. The map also follows a location set from
outside the step, and a move asked for before the map has drawn now waits for
it instead of being lost.

## Database (approved: "2 columns on technicians")

`technicians` is one of the frozen RB-CARS tables; the user approved the
change. Migration `20261117000007_technician_work_types.sql`:

- `offers_home_service`, `offers_shop_repair` - boolean, NOT NULL, default
  true, and `check (offers_home_service or offers_shop_repair)`.
- **Every technician already registered is set to both**, explicitly, as the
  user asked - nobody drops out of matching.
- `matching_candidates` carries both columns.
- `match_technicians_for_job` (ranks 4+) gates on them with the same rule.
- No RLS change. A technician writes their own row through the existing update
  policy; `guard_technician_self_update()` lists the columns they may not
  touch, and these are not among them.

The shop itself is the existing `shop_latitude` / `shop_longitude` /
`shop_name`.

## Matching

`match-technician/scoring/work_type.ts`, a Stage 1 hard gate beside the
identity gates:

| `jobs.service_path` | Only technicians with |
| --- | --- |
| `home_service` | `offers_home_service = true` |
| `pickup` (Shop Repair) | `offers_shop_repair = true` |
| `it_community` | not matched at all, as before |

A gate, not a weight: a client who chose Shop Repair and is offered someone
with no shop has not been given a worse match, they have been given a wrong
one. A missing flag counts as yes, so a function deployed before the
migration keeps matching everyone. The decline cascade (`job-response`) and
the urgent re-match (`urgent-offer-sweep`) use the same engine.

## Deploying, in this order

```sh
npx supabase db push --remote                                    # 20261117000007
npx supabase functions deploy match-technician job-response urgent-offer-sweep --use-api
```

Then rebuild the app.

**Deployed 2026-11-17** at the user's "push it": the migration is applied
(verified: all 6 technicians set to both, the check constraint present, the
view carries the columns, the list function gated) and the three functions
answer their own "Sign in required" / "Not authorised". None of the 6
technicians has a shop pinned yet; they can pin one in Profile → "Photo and
workshop" (saving there with Shop Repair on asks for the pin).

## Tests

- `tool/sql_tests/trust_badge` → `npm run test:work-types` (8 checks: the
  backfill, the check, the default, the view, the list gate both ways).
- `supabase/functions/match-technician/scoring/work_type.test.ts` (12).
- `test/features/onboarding/work_type_step_test.dart` (11): the step order,
  the controller rules, the descriptions, the shop map, a small phone at large
  text, and the map finding the user on its own or failing quietly.

## Also in this change

The "Back to login" button on the submitted-registration screen is a SUGO
button now (navy fill; an outline beside "Retake my photos"). It was a plain
Material outline that matched nothing else in the app.

## Rain and heavy traffic (2026-11-22)

The same step now ends with **Travelling to clients**, two questions every
technician must answer before Continue:

| Question | Answers | Column (migration 20261122000001) |
| --- | --- | --- |
| Will you still go to a client when it is raining? | Yes, even in heavy rain or a storm / Yes, but not in heavy rain or a storm / No, I do not travel in the rain | `rain_travel`: `any` / `not_heavy` / `never` |
| Will you still go when traffic is heavy? | Yes, I still go in heavy traffic / No, I avoid heavy traffic | `heavy_traffic_travel`: true / false |

Nothing is preselected. The recap shows them ("Even in heavy rain · Goes in
heavy traffic"), and Edit profile shows the same two questions, so a technician
registered before today can answer there. Their columns are null until they do,
and null is scored exactly as before.

Matching uses the answers in Stage 2's **Weather & traffic readiness** signal,
only while it is raining or the traffic is heavy at the job. See
`docs/rb-cars.md`, section 4, for the formula and a worked example.

Deploy: `db push` (the migration adds the columns and re-creates
`matching_candidates` with them), then `match-technician`, `job-response` and
`urgent-offer-sweep`, then the app. The app reads and writes the new columns, so
it must not ship before the migration is applied.
