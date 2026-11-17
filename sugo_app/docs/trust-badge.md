# Progressive Trust Badge

Added 2026-11-15. A technician moves up an ordered, three-rung ladder by
meeting objective criteria, and down it when a dispute or their own record says
so. The rules are explicit comparisons, with no machine learning.

| Rung | Earned when | Lost when |
|---|---|---|
| **1. ID Verified** | an admin approved their ID and selfie, **and** their email is confirmed | only by an admin changing the identity decision. Never automatic. |
| **2. Skill Verified** (per specialization) | ID Verified, **and** at least one specialization proven by a passed assessment **or** an admin-approved certificate | a dispute remedy de-verifies their last proven specialization |
| **3. Community Trusted** | Skill Verified, **and all five**: ≥ 50 completed jobs · ≥ 4.5 average rating · ≥ 90% response rate · 0 open or upheld disputes against them · < 10% cancellation rate | falling below **any** of the five, automatically |

## One source of truth

- **The level** is stored in `technicians.badge`, an existing column that was
  already guarded against the technician editing it and already read
  everywhere. Only `evaluate_technician_badge()` writes it.
- **Which specializations are verified** isn't stored a second time. It is
  `technician_specializations.verified`, written by the assessment, the
  certificate review and the dispute remedy.

Three things read those two values and nothing else:

| Reader | How |
|---|---|
| Profile and match card | the badge pill; the card shows the badge **for that job** |
| Client preference filter | "minimum trust badge" ≥ the technician's rung for this job |
| RB-CARS Stage 1 | the Trust Badge criterion (the factor keyed `verification_tier`): same weight, same 0.55 / 0.80 / 1.00 scores, now read from the badge |

**Per-job rung.** Skill verification is per specialization, so a technician's
rung for one job is their stored badge, capped at ID Verified unless a
verified specialization covers that job's device. A technician skill-verified
only for Phone/Tablet is therefore rung 1 on a PC Building job. They're
excluded when the client requires Skill Verified, and scored at the ID level.
It is *not* a universal hard gate: that was considered and rejected, because
it would empty Top 3s while few technicians have passed assessments.

## The metrics, from real data

| Metric | Computed as |
|---|---|
| completed_jobs | `jobs` with `status = 'completed'` assigned to them |
| avg_rating | mean of `job_outcomes.final_rating` (the same mean shown as their rating) |
| response_rate | offers answered within **24 h** ÷ (answered + answered late + still waiting past 24 h + missed) |
| disputes | client-raised reports on their jobs that are **open** or **upheld** |
| cancellation_rate | technician cancellations after acceptance ÷ accepted jobs |

Every threshold lives in one function, `trust_badge_rules()`. The ladder
itself is the pure function `trust_badge_level()`.

### What was missing, and was added (approved by the user)

- **`job_matches.offered_at` / `responded_at`**: nothing recorded when an
  offer was sent or answered. A trigger stamps both. Answers from before the
  migration count as on time, since the technician did answer.
- **`offer_misses`**: when a client withdraws an unanswered offer, it reverts
  to `shortlisted`, and re-matching or editing deletes it. A trigger logs any
  offer left unanswered for more than 24 h before either happens. A client who
  withdraws within 24 h doesn't count against the technician.
- **`job_disputes.outcome` / `remedy` / `remedy_specialization`**: "lost" and
  "skill de-verification" weren't recordable. Earlier decisions were
  backfilled: "Mark resolved" = upheld, "Close without action" = not upheld.
- **`technician_verification_documents.specialization`**: lets a certificate
  prove one specialization, chosen by the admin on approval.

### Adapted from the brief

- **No phone check in ID Verified.** Phone verification was removed from the
  app in September (no free SMS route). Email confirmation is the contact
  check that exists.
- **Cancellation rate is 0 for everyone.** No screen lets a technician cancel
  after accepting. The rule is wired, so it becomes meaningful the day such an
  action exists.

## Downgrades

- **Thresholds**: Community Trusted is recomputed on every relevant event, so
  dropping to 88% response reverts to Skill Verified on the next event or the
  nightly sweep.
- **Dispute remedy "skill de-verification"** drops exactly **one** level from
  where the technician stood *without that report*:
  - Community Trusted → Skill Verified. The upheld finding itself blocks
    Community Trusted, so no skill is taken away.
  - Skill Verified → ID Verified **for that specialization**. Its rows lose
    `verified`; other specializations keep theirs.

  "Without that report" matters: an open client report already costs
  Community Trusted, so judging by the live level would have removed two
  levels. Testing the migration in PGlite caught this and it was fixed.
- **It sticks.** An old passed assessment no longer re-verifies a
  specialization deleted and re-added after a de-verification. The technician
  may retake the assessment, which is how the skill is earned back.
- **Never below ID Verified.** Nothing automatic touches identity.

## When it recomputes

Postgres triggers, not Laravel. The events are written by edge functions, SQL
functions **and** the admin console, and a trigger is the one place they all
pass through.

| Event | Trigger on |
|---|---|
| job completion, cancellation | `jobs.status` / `assigned_technician_id`; `job_outcomes` |
| a new or changed rating | `job_outcomes.final_rating` (synced from reviews) |
| a dispute opened or decided | `job_disputes` |
| an offer answered, withdrawn or cleared | `job_matches` leaving `offered` |
| an assessment, certificate or de-verification | `technician_specializations.verified` |
| an identity decision | `identity_verifications.status` |

A **nightly pg_cron job** (02:00 Manila) catches the one change no event
announces: an offer crossing the 24 h window while nobody touches it. The
technician's own progress card re-evaluates before it answers.

The `technicians` guard trigger refuses a badge change made from the
technician's own session. The evaluator sets a transaction-local flag the guard
lets through, so a technician's own action (removing a specialization, say)
can still move their badge. They can't set the flag themselves.

## Where it shows

- **Technician dashboard → Trust badge**: their pill, the next rung, which
  specializations are verified, and every threshold with a tick or a progress
  bar ("38 / 50 jobs, rating 4.6, response 92%").
- **Match card**: the badge for this job, from Skill Verified up (ID Verified
  already has the blue check).
- **Technician profile (client view)**: the pill, its meaning, and "Skill
  verified for …".
- **Admin → Disputes**: finding (upheld / not upheld), remedy, specialization.
- **Admin → ID review**: "Proves competency in …" on each pending certificate.

## Files

| Layer | File |
|---|---|
| Migration | `supabase/migrations/20261115000002_progressive_trust_badge.sql` |
| Engine | `scoring/preferences.ts` (`trustRungOf`), `scoring/suitability.ts`, `scoring/rank.ts`, `scoring/constants.ts` |
| Engine tests | `scoring/preferences.test.ts` (`node --experimental-strip-types`) |
| App model | `lib/features/rb_cars/models/trust_badge.dart` |
| Pill | `lib/features/rb_cars/widgets/trust_badge_pill.dart` |
| Progress card | `lib/features/technician/widgets/trust_badge_progress_card.dart` |
| Admin | `DisputeController`, `VerificationController`, `app/Support/Specializations.php` and their views |

## Testing the SQL

There's no local Supabase (no Docker), so the migration was applied to a stub
schema in **PGlite** (Postgres compiled to WebAssembly, run from Node). 40
checks passed against real SQL: all four acceptance criteria, the offer clock,
the one-level rule, de-verification sticking, the retake, the guard,
certificates, and the constraint changes. To re-run it:

```sh
cd tool/sql_tests/trust_badge
npm install
npm test
```

The stub schema is in `tool/`, not `supabase/tests/`: `supabase test db` runs
every `.sql` file in that folder as a pgTAP test.

## Deploying, in this order

1. `supabase db push`, which applies `20261115000001` and `20261115000002`.
   The second backfills every technician's badge.
2. `supabase functions deploy match-technician --use-api` and
   `supabase functions deploy job-response --use-api` (it bundles the engine).
3. Deploy the admin panel.
4. Ship the app.

## Known limitations

- **Lost disputes count forever.** That's the brief taken literally ("== 0"):
  one upheld client report permanently bars Community Trusted. A time window
  would be a policy change.
- **Response timing starts at deploy.** Earlier answers have no timestamps and
  count as on time.
- **The email check proves nothing yet.** The project has "Confirm email"
  turned off (`enable_confirmations = false`), so Supabase marks every address
  confirmed at sign-up. Checked live on 2026-11-15: all 8 accounts were
  confirmed within 5 seconds of signing up. ID Verified therefore rests on the
  admin's ID + selfie approval. Turning confirmation on needs (a) the start of
  registration reworked, because sign-up no longer returns a session until
  the link is clicked, and (b) a custom SMTP sender, because Supabase's
  built-in one is rate-limited to a few emails an hour. Both are deliberately
  left until after the defence.
