# Book-and-cancel cooldown

Added 2026-11-17 at the user's request, including the new table.

## The problem

A client could book a technician, cancel, and book again as often as they
liked. Every booking reaches a real person. On an urgent job it is a
full-screen alert that buzzes their phone. Nothing remembered the cancels:
"Delete request" erases the job, and "Cancel request" puts the offer back on
the shortlist. So there was nothing to count.

## The rule

| | |
|---|---|
| **A cancel** | "Cancel request", or "Delete request" while a technician is booked (`job_matches.status = 'offered'`) and has not answered. Deleting a post nobody was booked on is **not** a cancel. |
| **The trigger** | 2 or more cancels within a rolling hour. |
| **The pause** | Booking is refused until 2 minutes after the **latest** cancel. Each further cancel in that hour starts a fresh 2 minutes. |
| **What is kept** | The post and its matches. The client can browse, message and edit; only booking waits. |

The three numbers are named constants in one place,
`booking_cooldown_until()` in migration `20261117000004_booking_cooldown.sql`.
Nothing else repeats them, so they cannot drift.

## Where each part lives

| Part | Where |
|---|---|
| The log | `booking_cancellations` (new table): client, job, technician, `withdraw`/`delete`, time. RLS: a client reads only their own rows; no insert, update or delete policy, so a client cannot erase their record. |
| The rule | `booking_cooldown_until(client)` (SQL, SECURITY DEFINER). A signed-in client may ask only about themselves. |
| "Cancel request" logs | `withdraw_technician_offer()` inserts the row and returns `booking_paused_until`. |
| "Delete request" logs | `job-response` `delete_job`, after the delete succeeds, only if an offer was pending. |
| **Enforcement** | `job-response` `select`, the only way a booking is ever made. Refuses with HTTP 429 and `retry_at`. |
| The countdown | "Choose a technician": `BookingPauseBanner` at the top; tapping Book during the pause says how long is left instead of opening the booking sheet. |
| The heads-up | The "Cancel your request?" dialogs state the rule before it applies, and a notice appears after the cancel that starts a pause. |

## Why the server enforces it

The app's countdown is only a display. If the rule lived in the app,
reinstalling it or clearing its data would reset it. The record is in the
database and the check is in the one function that books, so every build of
the app, and any direct call, meets the same rule.

## Why a failed check lets the booking through

The pause is anti-abuse, not a safety gate. If the check itself fails (the
migration not applied yet, a network error), refusing every booking for every
client would be far worse than letting one troll book once more. So
`job-response` logs the error and treats it as "not paused". The app does the
same: a failed check never stops the matches from loading.

## Deploying, in this order

1. `supabase db push --remote`: migration `20261117000004`.
2. `supabase functions deploy job-response --use-api`.
3. Rebuild the app.

Any other order is safe, just inactive until all three are out. A
`job-response` that is ahead of the database fails open, and an app that is
ahead of either reads "not paused".

## Tests

- SQL, in PGlite (15 checks: the rule's edges, the withdraw logging, RLS):
  `cd tool/sql_tests/trust_badge && npm run test:booking-cooldown`
- Flutter: `test/features/rb_cars/booking_cooldown_test.dart` (parsing, the
  provider turning a refusal into a countdown, the banner).
- The TypeScript in `job-response` was **not** type-checked locally: Deno is
  not installed on the dev machine. The deploy compiles it.

## Known limitations

- **It slows a troll; it does not stop one.** The pause is a flat 2 minutes,
  so a determined client can still book once every 2 minutes. Escalating
  pauses (2, then 5, then 15 minutes) would be the next step.
- **The banner uses the phone's clock; the server uses its own.** If the
  phone's clock is wrong, the banner may end early or late. The server
  decides. A Book tap after an early end is refused, and the banner comes
  back with the server's time.
- **Honest clients can hit it.** Changing your mind twice within an hour
  pauses you too. The wording explains rather than accuses, and the wait is
  short.
- **No admin view yet.** The log is in the database (service role can read
  it), but the admin panel does not show it.
