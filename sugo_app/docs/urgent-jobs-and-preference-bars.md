# Urgent jobs and preference bars

These changes were added on 2026-11-17 at the user's request.

## 1. Schedule: Flexible or Urgent

The "This week" option was removed. A job saved earlier with a seven-day
deadline now reads back as Flexible. `jobs.urgency` is unchanged:
`need_today` means Urgent and `can_wait` means Flexible.

## 2. The urgent fee: 20% of the labor fee

For example, a ₱600 labor fee gets a **₱120 urgent fee**, and the total is
₱600 + ₱120 + the travel or delivery fee.

| Where | What it shows |
| --- | --- |
| Review step, before posting | "Urgent fee (20%) +₱120" |
| Booking sheet, before sending | A line for the urgent fee, included in the estimated total |
| "Request sent" screen, job detail, bookings list, home card | The price including the urgent fee |
| Technician: request card, View task, accept dialog, urgent alert | "Labor ₱600 + urgent ₱120" |

The fee is worked out in `JobPrice` / `LaborPriceCatalog.urgentFee` from the
job's own urgency, the same way as the labor fee. **Nothing new is
stored.** When the labor fee is per unit (₱800/camera), the screen says
"+20% of labor" rather than inventing a number.

## 3. Preference bars on the matching screen

Each preference the client set on post task becomes a bar on every match
card, in the same form as the Match and Acceptance bars:

| Bar | How the percentage is worked out |
| --- | --- |
| Location | 100% within the limit. Beyond it, the limit as a share of the distance (5 km limit, 12.4 km away: 40%). |
| Skills | The matcher's own Stage 1 skill score for the job (specialisation and skill-tag factors) |
| Rating | 100% at or above the minimum. Below it, the rating as a share of the minimum. |
| Trust badge | 100% at or above the wanted rung. Below it, the rung held as a share of the rung wanted (Skill verified against Community Trusted: 67%). |
| Availability | 100% when free, 40% when on another job, 0% when on leave |

A summary pill reads "Meets all" or, for example, "2 of 4 met".

### When nobody is within the distance limit

Before, preferences that left nobody gave an empty screen with "try
relaxing them". Now, **when the distance limit is the only thing in the way**,
the engine shows the nearest technicians who meet every other preference,
with a banner such as "No technician within 5 km - the nearest is 12.4 km
away."

- The logic is in `distanceFallback()` in `match-technician/scoring/preferences.ts`.
- The note is saved in each match's existing `score_breakdown`
  (`preference_fallback`), so it shows on every visit.
- No schema change was needed.
- Tests are in `preferences.test.ts`.

## 4. Urgent requests: hard notification and a 5-minute hand-off

1. The client sends the request. The technician gets a **hard notification**:
   - on Android, the `sugo_urgent` channel at full importance (sound,
     vibration, heads-up);
   - on iOS, time-sensitive delivery;
   - with the app open, a **full-screen alert** that buzzes and shows the
     countdown, with Accept, View task and Decline.
2. The **countdown** starts at 5:00 from `job_matches.offered_at` and
   appears in three places: the technician's request card, the alert, and
   the client's home card and "Request sent" screen.
3. If nobody accepts in 5 minutes, the `urgent-offer-sweep` edge function
   (run by pg_cron every 30 seconds) does the following:
   - It marks the request `declined`, but only if it is still waiting. A
     technician who accepts at 4:59 wins.
   - It sends the request to the **next technician on the shortlist**,
     skipping anyone on vacation or already on a job.
   - If the shortlist is used up, it re-runs the matcher without everyone
     already asked, and offers the request to the new top pick.
   - It notifies the new technician (another hard notification with a fresh 5
     minutes), the client ("your urgent request moved on"), and the technician
     who let it lapse.

**Design decision:** since 2026-09-16, a declined request goes back to the
client to choose again. That way, no technician is handed a job that no
client picked. The user asked for automatic hand-off on urgent jobs, so the
sweep touches **urgent jobs only**, and flexible jobs keep the
client-chooses rule. A timeout is recorded as a decline.

**Schema:**
- The frozen RB-CARS tables are not changed. The sweep uses the existing
  `offered_at` and `urgency` columns and the existing `declined` status.
- One migration schedules the cron job.
- One appends `offered_at` to the `client_job_technicians` view, so the
  client's home card can show the clock.

## Deploy order

1. `npx supabase db push --remote --yes`. This applies
   `20261117000002_urgent_offer_sweep_cron.sql` and
   `20261117000003_client_job_technicians_offered_at.sql`.
2. `npx supabase functions deploy urgent-offer-sweep --use-api --yes`. The
   function uses the existing `CRON_SECRET` and the vault's `cron_secret`.
3. `npx supabase functions deploy job-response --use-api --yes` and
   `npx supabase functions deploy match-technician --use-api --yes`.
4. Rebuild the app (not a hot restart). `MainActivity.kt` now creates the
   urgent notification channel.
