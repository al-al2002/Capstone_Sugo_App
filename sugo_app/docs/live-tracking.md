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
| Client dropping it off (2026-11-17) | `dropping_off` | **client** | **technician** |

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

## The client's trip IN: drop-off (2026-11-17)

A Shop Repair booked with "I'll bring it" had no tracking at all until the
technician tapped "Unit received". Now the client's trip *to* the shop runs
through the same machinery as the collection trip above. Approved by the user
("Yes, new stage"); migration `20261117000006_drop_off_trip.sql`.

- **A new stage, `dropping_off`**, before `in_repair`, used only on a drop-off:
  `dropping_off → in_repair → ready_for_collection → delivered`. No new table
  or column, and RLS is unchanged.
- **"I'm on my way" creates the row.** On a drop-off there is no tracking row
  until the unit arrives, so `start_collection_trip()` inserts one at
  `dropping_off` when the job's own client taps it on a confirmed self
  drop-off. The row belongs to the assigned technician, so their existing
  update policy lets them move it on. `share_collection_position()` and
  `end_collection_trip()` accept both client stages.
- **"Unit received"** moves the row to `in_repair`. The stage change wipes the
  client's position (guard rule B), so their location is gone the moment the
  unit changes hands.
- **Edge functions**: `CLIENT_TRIP_STAGES` (`_shared/eta_sampler.ts`) lists both
  client legs, so `tracking-eta` lets the client sample, `tracking-eta-sweep`
  picks up their trip when the phone goes quiet, `job-route` live mode draws
  their road, and the destination resolves to the shop. `notify-event` says
  "bringing the {device} to your shop" instead of "coming to collect".

**What each side sees:**

| | Client (the drop-off card: job page, tracking screen) | Technician (drop-off screen) |
| --- | --- | --- |
| Before setting off | Route to the shop, **"Call {technician}"** with the number, "I'm on my way" | "Waiting for the client to set off", "Unit received" |
| On the way | "On your way to the shop"; trip card **"You arrive in 2 min · Weather is good and traffic is light"** | The client on the map (`ClientTripCard`), trip card **"Your client arrives in 2 min"**, push "… is on the way" |
| Running late | Trip card: "Running about 10 minutes behind · Slowed by heavy traffic. Your technician can see why." | Pop-up and push **"Your client is running late"**, with the cause; trip card "Delayed by heavy traffic." |
| Arrived | "You've arrived. Hand it over…" | "The client has arrived. Take the unit, then tap Unit received." |

The trip card's sentences flip on who travels (`TripConditions.clientTravels`):
the traveller reads "you", the person waiting reads "your client" or "your
technician". The collection trip gained the same card on both sides.

The technician's number comes from `technician_profile`, released once the
booking is confirmed - the same gate as the shop location.

Tests: `tool/sql_tests/trust_badge` → `npm run test:drop-off-trip` (20 checks),
`test/features/tracking/drop_off_trip_test.dart` (15).

## Location switches itself on

Every trip button does the location work for the person (2026-09-29):
"Start trip", "I'm on my way", and any pickup stage that travels, such as
"Start the delivery".

1. **Permission** is requested on the spot.
2. **If the phone's location is off, on Android**, one position is requested.
   Google Play services answers with its own "Turn on location?" dialog inside
   the app, so one tap is enough and nobody has to go to Settings.
3. **What cannot be fixed from inside the app** gets an error with a
   **Settings** button to the right page:
   - the dialog was declined;
   - permission was refused for good;
   - iOS or the web, where an app cannot switch location on.
4. **Opening a trip screen mid-trip resumes sharing without a tap.** This
   covers the technician on the way or delivering, and the client coming to
   collect. A forgotten switch no longer leaves the other person watching a
   frozen pin.

A pickup stage that travels still will not start until location is on. "On the
way" with nothing on the map would read as a stalled technician. The difference
is that the button now turns location on itself instead of waiting for someone
to remember the switch.

## The route on the map

The tracking maps draw the **road route** of the leg in progress (`job-route`,
live mode). The person watching sees the streets being driven: the client
following a technician, or a technician waiting for a collecting client.

- **The origin is not sent by the app.** The server takes it from the
  traveller's last position in `job_tracking` and resolves the destination the
  same way the ETA does (`leg_destination.ts`). Either person on the job may
  ask, but only while a leg is moving.
- **It is fetched sparingly** (`TrackingMap`):
  - once when the map opens;
  - when the stage changes;
  - when the traveller is more than 200 m off the drawn route, and then at most
    once a minute.
- **Between fetches the line is trimmed** to start at the moving marker
  (`routeAhead`), so it shrinks as they drive without another request.
- **With no route** (no road between the points, or the provider is down), it
  falls back to the dotted straight line.

The maps themselves share `lib/core/widgets/sugo_map.dart`:

- `@2x` tiles on high-density phones, which removes the blur;
- the calmer `dataviz` style, so the navy route and orange pins stand out;
- one destination pin with a label;
- one travelling marker, which pulses only while the position is live.

## The truck

`SugoTruckDrive` shows a truck driving along a road. It appears:

- on the client's tracking sheet;
- on the technician's trip screens (home visit, and the travelling pickup
  legs).

The map marker for every technician leg is a truck too.

The truck stays in place while the road runs beneath it. That says "moving"
without claiming "how far"; the map and the arrival time answer that from real
data. It drives only while the position is live. A stale position parks and
greys the truck, and reduced motion makes it a still picture.

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

## The trip card: arrival, weather and traffic (2026-11-17)

On every leg where the technician travels (home service; shop pickup's
"heading to pickup", "collected", "heading to the shop"; and delivery), both
sides now see the same card:

> **YOUR TECHNICIAN ARRIVES IN · 20 min** · to your home · 4.2 km · Updated just now
> Weather **Good** · Traffic **Light**
> ✓ Weather is good and traffic is light. On schedule.

The technician's version says "You arrive in" and "to the client".

**Where the facts come from.** The sampler already fetched TomTom traffic and
OpenWeatherMap weather on every sample, to compute the ETA and to blame a
delay. Until now it threw the labels away. Migration `20261117000005` keeps
them on `job_tracking` (`traffic_label`, `traffic_congestion`,
`weather_label`, `weather_severity`). The user chose this over asking the
weather service separately. It costs no extra API call, and the card and the
delay pop-up come from the **same sample**, so the card can never say
"traffic is light" while the pop-up says "delayed by heavy traffic".

**Only the server writes them.** The update guard keeps the app from changing
them (a technician must not be able to report "clear roads" to cover a late
arrival), and a new insert guard empties them when the app creates the row.
A new leg clears them, like the ETA columns. Tested in PGlite:
`npm run test:tracking-conditions` in `tool/sql_tests/trust_badge` (7 checks).

**Levels use the server's own lines.** Traffic uses the five words of
`describe()` in `tomtom.ts`. Weather turns "Bad" at severity 0.4, the line at
which the sampler blames a delay on the weather. So a "Bad" tile and "delayed
by bad weather" always agree. Readings that are missing say "Checking…"
before the first sample and "Not available" after it, and never a guess.

**The animations mean something** (`condition_glyphs.dart`):

- The sun turns slowly in good weather, a cloud drifts in fair weather, and
  rain falls in bad.
- The cars' speed is the traffic: quick on clear roads, crawling with brake
  lights when it is heavy, and stopped at a barrier for a road closure.
- The countdown rolls to its new value, and the header warms from navy to
  amber when the trip is late.
- Under reduced motion everything holds a still frame that still reads
  correctly.

**The delay, for each side.** The client keeps the pop-up, now redesigned. It
opens on an animated picture of the cause (rain, crawling cars, both, or a
ticking clock when no cause was found) and shows the new arrival time. The
picture plays three cycles and stops, because a pop-up is read once. The
technician gets a strip inside the card instead of a pop-up, because **they
are driving**, and a modal dialog over the road is the wrong thing at that
moment.

The card replaced the old ETA tiles, the delay banner and the weather chip on
the client's screen. `WeatherChip` and `TrackingService.weatherFor` were
deleted. The `job-weather` function is still deployed, but the app no longer
calls it.

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
npx supabase functions deploy job-route --use-api
```

- **`job-route`** has the live mode for the road route on the tracking maps
  (added later on 2026-09-29). Until it is deployed, the maps show the dotted
  straight line.

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

### Deploying the trip card (2026-11-17)

```sh
npx supabase db push --remote                       # 20261117000005, FIRST
npx supabase functions deploy tracking-eta tracking-eta-sweep --use-api
```

**The order matters.** The sampler writes the new columns in the same update
as the ETA. A function deployed before the migration would have that whole
update refused, so the ETA itself would stop being saved. The app tolerates
both states: with no labels it shows "Checking…", and with no new app the
columns are ignored.

### Deploying the drop-off trip (2026-11-17)

```sh
npx supabase db push --remote                       # 20261117000006, FIRST
npx supabase functions deploy tracking-eta tracking-eta-sweep job-route notify-event --use-api
```

Until the migration is pushed, "I'm on my way" on a drop-off fails ("There is
nothing to collect for this job"), because the live function only knows the
collection stage. The collection trip keeps working in every order.

## Not done

- **Background location.** Sharing runs only while the trip screen is alive;
  the sweep covers the gap from the last known position. Continuous background
  location would need the Android foreground-service permission and a stronger
  privacy case.
- **Road distance.** The ETA is straight-line distance over sampled traffic
  speed, not a routed time, which is why every figure is "about" and rounded to
  five minutes.
