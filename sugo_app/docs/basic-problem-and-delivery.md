# Basic problems and shop delivery

Added 2026-11-16. After the client describes the problem, SUGO suggests the
free Technician Community when the problem looks basic, and lets the client
choose one of three options. Shop Repair adds a choice of how the unit
travels, with the fee shown before the client sends a request.

## 1. Basic symptom detection

- **Rule-based and free.** No AI service is called.
- **One file to edit:** `lib/features/rb_cars/config/basic_problems.dart`.
  - `basicProblemKeywords`: phrases (English and Taglish), matched as whole
    words in the picked issue's label and in the client's "What happened?"
    text. Whole words means "hang" does not fire on "change".
  - `basicProblemIssueCodes`: issue categories that are basic whatever the
    client types (slow or freezing, battery not charging, no internet, ...).
  - The card's words.
- **The card's words** (in English since 2026-11-17; they were Filipino):
  *"This looks like a basic problem. Try the Technician Community first: it's
  free, and you can still book a technician if the tips do not fix it."*

### The suggestion follows the symptom (2026-11-17)

Before this date the card and the "Suggested" badge came from two different
rules, so a basic issue could show "try the community" while Home Service
carried the badge. Now one rule decides both, in
`ClassificationResult._fromIssue` (`models/problem_catalog.dart`), in this
order:

| # | When | Suggested | Card |
|---|---|---|---|
| 1 | Visible damage, or the issue's route is Shop pickup | **Shop Repair** (appliances: Home Service, too big to move) | no |
| 2 | A basic repair: on the basic list, route Home Service or Remote assist | **Technician Community** | yes |
| 3 | Anything else | the issue's own route (Home Service, or the community for remote assist) | no |

- **"Needs diagnosis" is never rule 2.** "Will not turn on", "Battery not
  charging" (laptop) and appliance "Not turning on" sound basic but stay Home
  Service, matched with a technician. That is the 2026-11-15 fix: a client
  reporting a dead laptop was getting advice instead of a technician.
- **Maintenance and installation are never rule 2**: they are work to book.
- **Only the issue moves the badge.** The description is typed on the next
  step; it can still bring the card up there as a nudge ("needs a restart"),
  but never when the suggestion is Shop Repair.
- **The client still chooses.** The suggestion is the first selection and the
  badge; any of the three can be picked, and the card offers the community
  back in one tap.

Basic issues today, and what each suggests:

| Issue | Suggested |
|---|---|
| Laptop: very slow or freezing | Community |
| Phone: software glitch | Community |
| Network: no internet, slow or intermittent, device will not connect | Community |
| Phone: battery draining, will not turn on; router will not turn on | Shop Repair (rule 1) |
| Laptop: will not turn on, battery not charging; appliance not turning on | Home Service (needs diagnosis) |

## 2. The three options

| Option | `service_path` | What happens |
|---|---|---|
| Post to Technician Community | `it_community` | Free. Posted as a question; technicians comment with tips |
| Home Service | `home_service` | RB-CARS matches a technician to come to the client |
| Shop Repair | `pickup` | Repaired at the technician's shop, then a second choice (below) |

Shop Repair's second choice, asked **only in the booking dialog** ("Send
your request to ..."), where the exact fee for that technician's shop is
known. Until 2026-11-17 it was also asked inside the Shop Repair card while
posting, and read back on step 6; that copy was removed at the user's request
because the booking dialog already asks it. A new post saves no
`delivery_option`; `job-response` saves the dialog's answer on send:

| `delivery_option` | Meaning | Fee |
|---|---|---|
| `self` | "I'll bring it / pick it up myself" | ₱0 |
| `delivery` | "Shop pickup/delivery" | by distance |

**"Still not fixed? Find a technician"** on the client's community post
turns it into a Home Service or Shop Repair booking with nothing retyped.

## 3. The delivery fee

```
billed km = distance rounded UP to the next whole km
billed km <= 3:  fee = 50
otherwise:       fee = 50 + 15 * (billed km - 3)
```

1 km → ₱50 · 3 km → ₱50 · 4 km → ₱65 · 5 km → ₱80 · 8 km → ₱125.

**Pickup and delivery is two trips (2026-11-17).** The technician drives to
the client to collect the unit and drives back with it fixed, so the saved
fee is twice the trip fee, at the user's request:

```
pickup and delivery fee = 2 x trip fee
```

1 km → ₱100 · 3 km → ₱100 · 4 km → ₱130 · 5 km → ₱160 · 8 km → ₱250.

- Shown as its two trips everywhere the price appears (booking dialog,
  booking confirmation, job page, the technician's offer and accept step).
  The user's example: 16.2 km bills as 17 km, one trip ₱50 + ₱15 × 14 =
  ₱260, so

  ```
  Pickup trip (16.2 km)   ₱260
  Delivery trip           ₱260
  ```

  ₱520 in all. A job booked before the rule (one trip charged) keeps one
  line, so it is never split into halves nobody paid (`JobPrice.feeLines`).
- A **home visit's travel fee stays one trip** (`LaborPriceCatalog.travelFee`
  = `DeliveryFee.oneWay`).
- Jobs booked before the change keep the fee saved on them.
- Server: `tripFee()` is one trip, `deliveryFee()` (saved by `job-response`
  and `urgent-offer-sweep`) is the two. App: `DeliveryFee.oneWay` / `.total`.

**The technician's route (2026-11-17).** On a pickup and delivery, the job
page shows the client's address on a map ("Route to the client, both
trips"), and the pickup screen shows "Collect it from the client - Trip 1 of
2" with **Show route** while heading out; the return trip's route is in the
delivery card from the bench onwards, as before.

- **The app's one function:** `DeliveryFee.calculate()` in
  `lib/features/rb_cars/models/delivery_fee.dart`. The existing home-visit
  `LaborPriceCatalog.travelFee` now uses it too. It was the same rule, kept as
  two copies.
- **The server's copy:** `supabase/functions/_shared/delivery_fee.ts`. The fee
  *saved* on a job is calculated on the server. Change the rates in both
  files; both test files pin the same distances, so a mismatch fails a test.

**Which shop.** Every technician has their own shop (`shop_*`, falling back to
`base_*`). The distance is to the **chosen** technician's shop, so:

- **posting:** nothing is asked (since 2026-11-17); the Shop Repair card says
  "You choose drop-off or pickup when you book a technician";
- **"Book this technician?" dialog:** the client picks Self or Delivery here,
  with the exact distance and fee for that technician, updating live when
  switching, before "Send request";
- **on send:** `job-response` recalculates the distance and fee from the shop
  location and saves both. The client never sees the shop's coordinates
  before booking, and can't send their own fee.

## 4. Drop-off (self)

- **Return trip:** set to client collection automatically
  (`job_return_preferences = client_pickup`). Since 2026-11-17 the client is
  never asked "How do you want it back?" on a drop-off: the job page shows
  "You'll collect it at the shop" instead, its card is titled "Drop-off and
  collection", the button reads "Repair progress" (then "Route to the shop"
  once it is ready), and the tracking screen's bench card no longer promises
  a delivery map.
- **Technician:** the offer card says "Client drops off". The job screen shows
  "Drop-off and collection", and "Unit received" starts tracking at
  `in_repair`; no pickup trip is ever created.
- **Client (route map, 2026-11-17):** once the technician accepts, the
  client gets **"Bring it to the shop"** (`tracking/widgets/drop_off_route_card.dart`):
  the road route from where they are to the technician's shop, drawn on the
  map with distance and a traffic-aware time, then **Start route** (the
  in-app route screen, which follows them and recalculates) and **Open in
  maps**. It shows:
  - at the top of the client's **job page**, in place of the "Delivery" card,
    which used to say "Tracking opens once your technician sets off to collect
    the unit" (no such trip exists on a drop-off);
  - on the **tracking screen**, where it replaces the pin-only card;
  - from the **home screen**: the booking card reads "Bring it to the shop"
    with a **Route to the shop** button.

  It disappears when the technician taps "Unit received" (tracking starts).

  **The trip itself (2026-11-17).** The card also shows the technician's
  number with a **Call** button, and "I'm on my way" / "I've arrived": the
  technician follows the client on a map with their arrival time, both sides
  see the traffic and weather on the way, and the technician gets a pop-up if
  the client runs late, with the cause. Details and deploy steps:
  `docs/live-tracking.md`, "The client's trip IN".

  **Where the shop comes from.** `technician_profile` releases the shop's name
  and pin once the client has a confirmed booking with that technician, so the
  map appears without the client's location. The road comes from `job-route`:
  the app sends only the client's position, and the server resolves the shop
  from the job (it opens because `job-response` set `client_pickup` when the
  client chose "I'll bring it"). No server change was needed.

  **Location is not asked for on arrival.** The route is drawn at once only if
  SUGO may already read the position (`TrackingService.locationAllowed`, which
  never prompts). Otherwise the card shows the shop and **Show my route**, and
  the permission prompt comes from that tap. One TomTom call per card.

## Database changes

Migration `20261116000001_shop_delivery_option.sql`, approved by the user:

```sql
alter table public.jobs
  add column delivery_option text check (delivery_option in ('self','delivery')),
  add column distance_km numeric(6,2) check (distance_km >= 0),
  add column delivery_fee integer check (delivery_fee >= 0);

-- only a shop repair may carry a delivery option
check (delivery_option is null or service_path = 'pickup')
-- bringing it yourself is free
check (delivery_option is distinct from 'self' or coalesce(delivery_fee, 0) = 0)
```

- **`service_type`** is the existing `jobs.service_path`; no new column.
- **Who writes what:** `job-response` writes `delivery_option`,
  `distance_km` and `delivery_fee` on select, from the booking dialog. A new
  post leaves `delivery_option` null; "Edit post" sends back whatever the job
  already has, through the edit whitelist.
- **No RLS change.**

## Deploying, in this order

1. `npx supabase db push --remote`
2. `npx supabase functions deploy job-response --use-api` and
   `npx supabase functions deploy match-technician --use-api` (the offer
   snapshot carries `delivery_option`).
3. Build and install the app.

A post that is not a shop repair sends no `delivery_option`, so it works even
before step 1.

## Tests

- `test/features/rb_cars/delivery_fee_test.dart`: 1, 3, 4, 5 and 8 km, plus
  rounding and the breakdown text.
- `supabase/functions/_shared/delivery_fee.test.ts`: the same cases on the
  server (`node --experimental-strip-types delivery_fee.test.ts`).
- `test/features/rb_cars/basic_problem_test.dart`:
  - detection, including whole-word matching
  - what the job model writes
  - the live fee switch
  - 48 dp tap targets
  - the suggestion card, in English, agreeing with the badge
  - which issues suggest the community, Shop Repair or Home Service
  - landscape, and a 320 px phone at large text
- `test/features/tracking/drop_off_route_card_test.dart`: the route drawn
  when location is allowed, no prompt until "Show my route", a refused
  permission, a shop with no pin, the job page (client only, drop-off only),
  the home card, full motion, and a 320 px phone at 1.5x text.

## Known limitations

- **Straight-line distance**, not road distance, as everywhere else in SUGO.
- **A shop job from before today** has no `delivery_option` and behaves as
  delivery, as it always did.
- **A technician with no shop or base location** gets an unpriced delivery fee
  (null), confirmed in chat, rather than a guessed one.
