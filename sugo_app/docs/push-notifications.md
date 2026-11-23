# Push notifications: every job update, app closed

Completed 2026-11-17, at the user's request: "notification all updates on task
and also the arrival on technician client when the phone is closed the app".

## How a push reaches a closed phone

Every push is sent by FCM with a visible `notification` (title and body) at
high priority (`_shared/fcm.ts`), so Android shows it in the tray even when
SUGO is closed. Tapping it starts the app and opens the right screen
(`NotificationRouter` → each dashboard's tap handler). When SUGO is already
open, Android shows nothing, so the dashboards show the same news as an
in-app message and refresh.

## Every push, by who receives it

**The client**

| When | Says | Opens | Sent by |
| --- | --- | --- | --- |
| Technician accepts | "Booking confirmed - Ryan accepted your laptop repair" | the job | `job-response` accept (NEW) |
| Technician accepts it as a shop repair | "Ryan will take it to the shop" | the job | `job-response` reroute (NEW) |
| Technician declines | "Ryan can't take this one - choose another" | Choose a technician | `job-response` decline (NEW); pop-up when open (2026-11-23) |
| Home visit switched to the shop | "Ryan is taking it to the shop" | the job | `job-response` needs-shop (NEW) |
| Technician sets off / on the way | "On the way to you" | live map | stage trigger |
| Technician almost there (3 min) | "Ryan is almost there - about 2 min away" | live map | ETA sampler (NEW) |
| Technician arrived (home visit) | "Your technician has arrived" | live map | stage trigger |
| Unit collected / at the shop / repair started | stage wording | live map | stage trigger |
| Repaired unit almost back (3 min) | "Your laptop is almost back" | live map | ETA sampler (NEW) |
| Out for delivery / ready for pick-up / delivered | stage wording | live map | stage trigger |
| Technician running late | "Running late - about 10 min, heavy traffic" | live map | ETA sampler |
| Urgent request passed on / unanswered | urgent wording | the request | `urgent-offer-sweep` |
| A message | the message | the chat | message trigger |
| Job completed | "Tap to rate them" | rating | `job-response` complete |

**The technician**

| When | Says | Opens | Sent by |
| --- | --- | --- | --- |
| A client books them | "New job request" (urgent: hard alert) | Home | `job-response` select |
| Client cancels the request | "Request cancelled" | Home | `withdraw_technician_offer` (NEW) |
| Client deletes the request | "Request cancelled" | Home | `job-response` delete (NEW) |
| Client sets off to the shop | "Juan is on the way" | pickup screen | `start_collection_trip` |
| Client almost there (3 min) | "Juan is almost there - bringing the unit" | pickup screen | ETA sampler (NEW) |
| Client arrives at the shop | "Juan has arrived - take it, then tap Unit received" | pickup screen | `end_collection_trip` (NEW) |
| Client running late | "Your client is running late" | pickup screen | ETA sampler |
| Client chooses delivery or pick-up | return-method wording | the job | return-method trigger |
| Urgent offer missed | urgent wording | Home | `urgent-offer-sweep` |
| A message / job completed by the client | as above | chat / job | as above |

## What was added (2026-11-17)

- **Migration `20261117000008_more_push_events.sql`** - two existing functions
  each gain one `push_event()` call; no table, column or policy changes:
  `withdraw_technician_offer` (type `withdrawn`) and `end_collection_trip`
  (type `arrived`, once per trip - tapping "I've arrived" twice tells the
  technician once).
- **`notify-event`** - the words for `withdrawn` and `arrived`.
- **`job-response`** - pushes on accept, reroute, decline, needs-shop and
  delete-with-a-pending-request.
- **ETA sampler** (`tracking-eta`, `tracking-eta-sweep`) - "almost there",
  `_shared/arrival.ts`: once, as the estimate crosses into the last 3
  minutes, on legs that end where someone is waiting (technician → client,
  repaired unit → client, client → shop). Stateless: the previous sample's
  estimate is on the row, so no column was needed.
- **The app** - tap routing for the new types (`arriving` opens the live map;
  `client_arriving` / `client_arrived` open the pickup screen;
  `request_cancelled` refreshes Home) and in-app messages when SUGO is open.

## The decline pop-up (2026-11-23)

At the user's request, a decline is now a pop-up when SUGO is open, not a
four-second snackbar: the request is waiting on the client again, so it holds
until read and offers the way forward.

- **`_shared/decline_notice.ts`** builds the decline push (same tray wording as
  before) and adds two data fields: `name` (the technician's first name) and
  `next` - `shortlist` (others from the match are still there), `more` (the
  shortlist ran out and a fresh match found more) or `none` (nobody else is
  free). Tested by `decline_notice.test.ts` (12 checks).
- **`DeclinedAlertDialog`** (`features/client/widgets`) - "Ryan can't take
  this one", a chip and a sentence for `next`, then **Choose another
  technician** (or **Open my request** when nobody is free) and **Later**.
  Raised by the client dashboard, which stays mounted under every client
  screen, so it shows over a chat or a booking too. An older server without
  `name`/`next` gets "Your technician can't take this one" and general words.
- **Tapping the tray push** (SUGO closed) now opens Choose a technician for
  the job (by its status) instead of the booking page.

Deploy: `job-response` (for `name`/`next`), then the app. Tests:
`test/features/client/declined_alert_dialog_test.dart` (6).

**Deployed 2026-11-23**: `job-response` is live with `name`/`next`; it
answers its own "Sign in required". Not yet seen on a real phone.

## One limit to know

"Almost there" and "running late" come from the traveller's live position,
which is shared while their trip screen is open (there is no background
location - see `live-tracking.md`, "Not done"). The person being told can
have SUGO closed; the person travelling needs their trip screen open, or the
estimate stops moving.

## Deploying, in this order

```sh
npx supabase db push --remote                        # 20261117000008
npx supabase functions deploy notify-event job-response tracking-eta tracking-eta-sweep --use-api
```

`job-response` also carries the two-trip pickup-and-delivery fee.

**Deployed 2026-11-17** at the user's request: the migration is applied (both
functions verified to call `push_event`), and `notify-event`, `job-response`,
`tracking-eta`, `tracking-eta-sweep` and `urgent-offer-sweep` (which shares
the two-trip fee) are deployed; each answers its own "Sign in required" /
"Not authorised". Not yet seen on two real phones.

## Tests

- `tool/sql_tests/trust_badge` → `npm run test:push-events` (6 checks: the
  cancel push, the arrival push once with its stage, a new trip announcing
  again, and only the client ending their trip).
- `supabase/functions/_shared/arrival.test.ts` (6): when "almost there" is
  said, and when it is not.
