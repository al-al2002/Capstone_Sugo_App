# Live tracking and delay alerts

How a client follows their technician, how a technician follows a client
coming to collect, and how whoever is waiting learns that the other is running
late. The home-visit trip, the client's collection trip and the in-app delay
pop-up were added on 2026-09-29.

## Who travels on each leg

| Leg | Stage | Who travels | Who watches and is told if it is late |
| --- | --- | --- | --- |
| Technician to a home visit | `heading_to_pickup` | technician | client |
| Technician to collect a unit | `heading_to_pickup` | technician | client |
| Unit to the shop | `collected`, `returning_to_shop` | technician | client |
| Delivery back | `out_for_delivery` | technician | client |
| Client collecting from the shop | `ready_for_collection` | **client** | **technician** |

## Two journeys, one table

| Journey | `jobs.service_path` | Trip | Stages used |
| --- | --- | --- | --- |
| Home visit | `home_service` | The technician drives to the client and repairs it there. | `heading_to_pickup` → `in_repair` |
| Workshop | `pickup` | The unit goes to the shop and comes back. | all seven, `heading_to_pickup` … `delivered` |

A home visit reuses two of the workshop's stages instead of adding new ones:

- **`heading_to_pickup`** is the same trip to the same address as the start of a
  pickup.
- **`in_repair`** is the repair under way with nothing moving.

Because the stages are shared, the table, the RLS policies, the ETA sampler, the
delay detection, the realtime feed and the push trigger all work unchanged, and
**no migration was needed**.

Only the *words* and the *route* differ, and `jobs.service_path` says which
journey a row is on. In the app, `TrackingJourney` (in `job_tracking.dart`)
supplies the right label, blurb, next move and timeline for each journey.

## The home-visit trip, end to end

1. **The technician taps "Trip to the client", then "Start trip"**
   (`HomeVisitTripScreen`).
   - Location permission comes first, then the `job_tracking` row is inserted
     at `heading_to_pickup`.
   - Opening the screen writes nothing, so looking up the address never tells
     the client "on the way".
2. **The database trigger (`job_tracking_push`) pushes the news.** The client
   receives "Your technician is on the way", heading to your address (from
   `notify-event`).
3. **Every position fix updates the row.** About every two minutes the
   technician's app asks `tracking-eta` to resample the ETA against live TomTom
   traffic and OpenWeatherMap weather at the destination.
   - If the app goes quiet, `tracking-eta-sweep` (pg_cron) keeps sampling from
     the last known position.
4. **The client sees a live map** of the technician, their address, the ETA and
   the weather there (`JobTrackingScreen`).
5. **The technician taps "I've arrived"**, and the row moves to `in_repair`.
   - Sharing stops and the map closes.
   - The stage-change trigger clears the ETA, so a finished trip can never be
     reported late.
   - The client is pushed "Your technician has arrived".
6. **The repair finishes through the normal "Mark as complete"**, not through
   a tracking stage.
   - If the unit cannot be fixed on site, "Cannot fix here - take to shop"
     reroutes the job.
   - The same row then continues as a workshop pickup.

## The client's trip to the shop

When the client chose to collect the repaired unit, the stage reaches
`ready_for_collection` and the unit waits on the shelf. That trip used to go
untracked. Since 2026-09-29 it runs through the same ETA and delay machinery,
pointed the other way.

1. **The client taps "I'm on my way"** (`CollectionTripPanel` on their tracking
   screen).
   - Location permission comes first. Then `start_collection_trip()` opens the
     trip and starts a fresh promise.
   - The technician is pushed "… is on the way" (`notify-event`, type
     `collection`).
2. **While that screen is open**, each fix goes to
   `share_collection_position()`. About every two minutes the client's app asks
   `tracking-eta` to resample. It is allowed to on this one stage only.
3. **The technician sees them** on the pickup-and-delivery screen
   (`ClientTripCard`): a person on the map heading for the shop, the arrival
   time, and a delay banner.
4. **If the client runs 10 minutes or more late**, with the cause when the data
   supports it, the technician gets:
   - the push "Your client is running late" if the app is closed;
   - the pop-up if it is open, from the delivery screen or anywhere on their
     dashboard.
5. **The client taps "I've arrived"** (`end_collection_trip()`). Their position
   is dropped and the delay cleared. The technician then marks it collected as
   before.

### How the data is kept

- **Separate columns for the client's position** (`client_latitude`,
  `client_longitude`, …). The technician's `latitude` and `longitude` are never
  shared between the two, so neither can overwrite the other.
- **The same ETA columns**, because on this leg they describe the client's trip.
- **RLS was not loosened.** The client reaches their columns only through the
  three functions, and each one checks that the caller is the job's client and
  that the unit really is waiting.
- **Direct writes are guarded.** The guard trigger puts back any server-owned
  column that an app writes directly. It now tests the database role, so the
  functions (running as their owner) can write while the apps (running as
  `authenticated`) cannot.
- **Privacy.** The client's position exists only during the trip. Arriving
  clears it, and so does any stage change. Nothing keeps a history.

## How "late" is decided

- **The promise.** The first ETA of a leg is frozen as `expected_arrival_at`.
  Every later sample writes `projected_arrival_at`, and the gap between the two
  is `delay_minutes`. An ETA that quietly slid forward would never be late,
  which is why the first estimate is kept.
- **The threshold** is 10 minutes (`DELAY_THRESHOLD_MINUTES`). Straight-line
  distance understates road distance by about 20–30%, so anything smaller would
  fire on the estimate's own noise.
- **The cause** is named only when the data supports it:
  - `traffic` when congestion is at least 0.35 or a road is closed;
  - `weather` when severity is at least 0.4 (rain and worse);
  - `both` when both hold.

  Otherwise `delay_reason` is null, and the app says "behind the original
  estimate". It never invents an excuse on the technician's behalf.

## Telling whoever is waiting

For the technician's legs, the client is waiting:

| Where the client is | What reaches them |
| --- | --- |
| App closed or in the background | A push, sent **once per leg** (`delay_notified_at`). |
| App open, on the home screen or any screen above it | The **pop-up**: "Running late", about N minutes behind, and the cause. On the home screen itself it offers "See live map". |
| On the tracking screen | The same pop-up, plus a banner in the sheet for as long as the delay lasts. |
| Later | A "Running late" item in the notification centre. |

For the client's trip to the shop, the technician gets the same three things
with "Your client is running late". The two checks are kept apart
(`DelayAlerts.isAlertable` and `isClientTripAlertable`), so a late client is
never told that their technician is late.

The pop-up shows **once per trip**. `DelayAlerts` keys it on the job and the
leg's promise, and remembers the key on the device. Two screens watching the
same trip therefore never both show it, and reopening the app does not repeat
it. A new leg has a new promise, so it can be late in its own right.

**Why a pop-up at all:** Android shows no push for the app in the foreground, so
a client with SUGO open on another screen would otherwise not hear. A foreground
push (`FirebaseMessaging.onMessage`) now makes the home screen re-read the trip.
The home screen follows the trip live only while someone is moving, because the
live feed polls every 15 seconds as a fallback to realtime.

## A bug fixed along the way

`heading_to_pickup` ("On the way to you") used to resolve to the **workshop**,
both in `_shared/leg_destination.ts` and in the tracking screen's map. The
client was shown an ETA and weather for a shop across town while their
technician was driving to them.

`job-route` already sent this leg to the client's address. Now all three agree
(`TrackingStage.headsToClient`). This also fixes the first leg of every
workshop pickup.

## Deploying

The app changes ship with the next build. The server half is one migration and
four edge functions. Run the migration **first**, because the functions read
its columns:

```sh
cd sugo_app
npx supabase db push
npx supabase functions deploy tracking-eta tracking-eta-sweep job-weather notify-event --use-api
```

- **`20260929000001_client_collection_trip`** adds the client columns, the three
  functions, and the reworked guard trigger.
- **`tracking-eta` and `tracking-eta-sweep`** bundle the sampler (the client's
  leg) and the fixed `leg_destination.ts`. `tracking-eta` also lets the client
  sample their own trip.
- **`job-weather`** bundles the fixed `leg_destination.ts`.
- **`notify-event`** has the home-visit wording and the `collection` push.

Until they are deployed:

- a home visit's ETA and weather are measured to the workshop;
- the "on the way" push says "to collect your …";
- "I'm on my way" fails, because its function does not exist yet;
- tapping a delay push opens nothing, because the old push carried no job id.

## Not done

- **Background location.** Sharing runs only while the trip screen is alive;
  the sweep covers the gap from the last known position. Continuous background
  location would need the Android foreground-service permission and a stronger
  privacy case.
- **Road distance.** The ETA is straight-line distance over sampled traffic
  speed, not a routed time, which is why every figure is "about" and rounded to
  five minutes.
