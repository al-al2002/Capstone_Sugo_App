# RB-CARS: Context-Aware Recommendation System

The matching engine behind SUGO. This is the document to read before a defence:
it covers what the system does, the exact arithmetic it does it with, and why
each decision was made that way.

Companion documents:

- `docs/third-party-apis.md` - registering TomTom, OpenWeatherMap, MapTiler
- `docs/edge-functions-setup.md` - Supabase CLI, secrets, deploy, cron

---

## 1. The problem

A client with a broken laptop does not know which technician to pick, and a
marketplace that just lists everyone by rating gets three things wrong:

1. **It ignores fit.** The highest-rated technician on the platform may only do
   aircon.
2. **It ignores reality.** The best-fitting technician may be fully booked, 30
   km away, in a thunderstorm, and priced above the client's budget.
3. **It concentrates work.** Rank by score alone and every job goes to the same
   person until they are saturated, so nobody else ever builds a record and the
   ranking calcifies.

RB-CARS answers all three with a two-stage score, live context, and a
workload-aware tie-break.

---

## 2. Architecture at a glance

```
Flutter (client)                      Supabase
─────────────────                     ────────────────────────────────────
job posting flow                      jobs           (RLS: own rows)
   │  insert via PostgREST  ────────► profiles       (RLS: own row)
   │
   │  functions.invoke                Edge functions (service role)
   ├─► match-technician ────────────► reads ALL technicians
   │                                  ├─► TomTom Traffic Flow    (secret key)
   │                                  ├─► OpenWeatherMap current (secret key)
   │                                  ├─► job_outcomes history
   │                                  └─► writes Top 3 to job_matches
   │
   ├─► job-response ───────────────► accept / reroute / decline / complete
   ├─► technician-directory ───────► public profile browse
   └─► aggregate-outcomes (cron) ──► nightly counter repair + accuracy audit

client review screen  ◄──── reads job_matches via RLS (own job)
```

### Why an edge function and not a database query

Three reasons, and it is worth being able to give all three.

1. **Secrets.** TomTom and OpenWeatherMap keys must not ship in an APK. The
   function holds them; the phone never sees them.
2. **Reach.** Ranking requires reading every technician. The
   `technicians_select_own` policy limits a normal user to one row. Only the
   service role can see the pool.
3. **Integrity.** `job_matches` and `job_outcomes` have select policies but no
   insert or update policies. A client that could write its own scores could
   rig the recommendations. All writes go through a function that first checks
   who the caller is.

That third point is the security seam: **elevated privilege plus an explicit
ownership check, never elevated privilege alone.** Every handler in
`supabase/functions/` resolves `callerId(req)` from the JWT and compares it to
the row it is about to touch.

---

## 3. Stage 1 - Suitability

*Can this technician fix this device, for this symptom, well?*

Deliberately free of live context, so it is reproducible: same data in, same
score out. Weights live in
`supabase/functions/match-technician/scoring/constants.ts`.

| Factor | Weight | 0..1 scored on |
| --- | --- | --- |
| Skill tag match | 0.35 | exact symptom tag = 1.0; token overlap = 0.35 + coverage x 0.55; device-only tag = 0.4 |
| Specialisation | 0.25 | device type in `specialization` = 1.0; empty = 0.35; mismatch = 0.15 |
| Tier | 0.15 | standard 0.50, pro 0.80, elite 1.00 |
| Verified | 0.15 | 1 or 0 |
| Diagnosis accuracy | 0.10 | the feedback signal, below |

Stage score is the weighted mean, so it is always in 0..1.

### Cold start

A newly verified technician has zero completed jobs. Without protection they
would score at the bottom of the accuracy factor forever, never get a job, and
never generate the data that would lift them. Two mitigations:

1. Their accuracy factor uses the **prior** (0.70), not zero. No evidence means
   *unknown*, not *bad*.
2. A **+0.08 boost** is added to the Stage 1 score when `is_verified` is true
   and `total_jobs` is 0, clamped to 1.0.

Verification is the gate, so this cannot be farmed by creating empty accounts.
The boost disappears the moment they complete their first job, at which point
real evidence takes over.

### Diagnosis accuracy: the feedback loop

Computed in `scoring/accuracy.ts` from `job_outcomes` joined to `jobs`.

**Relevance weighting.** An outcome on the same device *and* symptom counts at
1.0. Same device, different symptom counts at 0.4. A different device counts for
nothing - being good at laptops says nothing about aircon.

**Shrinkage toward a prior.** Raw `correct / total` is meaningless at n = 1,
where one lucky job reads as a perfect record. So:

```
                correct + 3 x 0.70
smoothed  =  ────────────────────────
                 total  + 3
```

Every technician starts at 0.70 and moves toward their observed rate as
evidence accumulates. It takes roughly three relevant jobs before their own
record outweighs the prior.

**Reroute discount.** A mid-job reroute means the on-site call was wrong and
cost the client a visit, so:

```
signal = smoothed x (1 - 0.30 x reroute_rate)
```

---

## 4. Stage 2 - Acceptance

*Will they take it, and turn up?*

| Factor | Weight | 0..1 scored on |
| --- | --- | --- |
| Budget fit | 0.25 | quote inside `budget_max` = 1.0, decaying to 0 at 2x the ceiling; no budget = 0.70 |
| Workload | 0.25 | `1 - min(workload, 5) / 5` |
| Urgency x path | 0.15 | lookup table, below |
| Traffic | 0.15 | `1 - congestion x travel_exposure` |
| Proximity | 0.10 | `1 - min(km, 25) / 25` |
| Weather | 0.10 | `1 - severity x travel_exposure` |

### Travel exposure

Traffic and weather are not applied flat. They are multiplied by how much the
chosen path actually involves travel:

| Path | Exposure |
| --- | --- |
| `home_service` | 1.00 |
| `pickup` | 0.60 |
| `it_community` | 0.10 |

Without this, a rainy afternoon would lower every candidate by the same amount,
change nothing about the ranking, and make all the printed numbers look worse
for no reason.

### Urgency crossed with path

The brief's requirement, made explicit as a table:

| | home_service | pickup | it_community |
| --- | --- | --- | --- |
| `need_today` | 1.00 | 0.55 | 0.40 |
| `can_wait` | 0.85 | 0.85 | 0.75 |

When the client needs it today, an on-site visit clearly beats shipping the unit
to a shop. When they can wait, path choice barely predicts acceptance, so the
scores sit close together and other factors decide.

### Graceful degradation

This is the detail most worth defending. A factor whose value is `null` is
**unavailable**, not zero. TomTom being down does not mean everyone is stuck in
traffic. `scoring/weighting.ts` drops null factors and **redistributes their
weight across the survivors**, so the remaining weights still sum to 1 and the
stage score stays comparable. The dropped factor simply never appears in the
breakdown.

If a missing API scored 0 instead, every candidate would fall by the same
amount, the ranking would be identical, and the displayed scores would be lies.

---

## 5. Combining and ranking

Since 2026-09-27 the ranking is the **recommendation score** from Stage 3
(section 5b). Before that it was a fixed blend:

```text
final = 0.60 x suitability + 0.40 x acceptance      (version 1, retired)
```

Suitability still outweighs everything else, for the same reason: a technician
who is available, close and cheap but cannot fix the device is a worse outcome
for the client than a slightly slower one who can.

---

## 5a. Rule-based weight selection (Step 3)

`scoring/rules.ts`. The weights in section 3 and 4 are right for an ordinary
request and wrong for an unusual one - in a downpour, when the client needs
someone today, distance matters far more than it does on a dry afternoon.

**Signals.** Once per job the engine derives yes/no facts from data it actually
has: `urgent` (needed today), `rain` (weather severity >= 0.5), `heavy_traffic`
(TomTom congestion >= 0.6, or a road closure), `on_site` (home service),
`appliance` / `technology` (the device type).

**Rules** are data, not branches - `MATCHING_RULES`:

| Rule | IF | THEN multiply |
| --- | --- | --- |
| Urgent visit in the rain | urgent AND rain AND on_site | distance x1.6, availability x1.4, weather x1.5; context fit x1.5, acceptance x1.2 |
| Heavy traffic on the way | heavy_traffic AND on_site | distance x1.5, traffic x1.5, availability x1.2; context fit x1.3 |
| Needed today | urgent | availability x1.3, workload x1.4, urgency fit x1.2 |
| Appliance repair | appliance | brand/device match x1.3, skill x1.2, tier x1.2, diagnosis accuracy x1.2 |

Multipliers compose when several rules fire, are **capped at x2.0** per factor,
and the stage is renormalised so its weights still sum to 1. A factor a rule
moved keeps its `base_weight` in the breakdown, so the detailed sheet prints
"x18%->27%".

**Why multipliers and not replacement weight tables.** A rule says "distance
matters more", not "distance is 27%". Multipliers compose; tables would need
one per combination of conditions and would drift from `constants.ts`.

**Fallback is automatic.** A signal whose source is down is absent, so its rule
does not fire and the base weights stand. TomTom down means no traffic rule -
distance still carries the ranking, exactly as the brief asks.

**Honest gaps.** The brief's example rule is "urgent + errand + rain". SUGO has
no errand category (jobs are laptop, phone, appliance, network), so the rule is
written against an on-site visit, which is the same situation for a repair.
There is no data on a technician's equipment or rain readiness, so no rule
pretends to weigh either.

## 5b. Stage 3 - Recommendation (Step 6)

`scoring/recommendation.ts`. Matching answers "who is qualified and
compatible?"; recommendation answers "which of them is most relevant to *this*
client, *now*?".

| Factor | Weight | 0..1 scored on |
| --- | --- | --- |
| Suitability | 0.45 | the Stage 1 score, after rules |
| Acceptance | 0.20 | the Stage 2 score, after rules |
| Context fit | 0.15 | mean of whichever apply: inside their service area; travel time at current speed (on-site); free today (urgent); short trip (rain + on-site) |
| Client preference | 0.10 | this client's history: rated them >= 4 stars 1.0, worked together 0.75, never booked 0.50, rated <= 2 stars 0.10 |
| Track record | 0.10 | mean of smoothed offer-acceptance rate (prior 0.75, weight 3) and log-scaled experience (1.0 at 50 jobs) |

Rules can re-weight this stage too. The result is stored as
`job_matches.final_score` and in `score_breakdown.recommendation`.

**Cold start, both sides.** A client with no past bookings has *no*
preferences - `client_preference` is null and dropped, and its weight is shared
out (the same rule as section 4's graceful degradation). Nobody is ranked on a
preference the client never showed. A technician who has never answered an
offer sits at the 0.75 prior.

**Not double-counted.** Rating is already a Stage 1 factor, so track record
leaves it out.

**Not counted at all: cancellations.** `jobs` records that a job was cancelled
but not who cancelled it. Holding a client's change of plans against the
technician would be unfair.

## 5c. Reasons a client reads (Part 17)

`scoring/reasons.ts` writes `recommendation.reasons`: sentences like "Passed
SUGO's assessment on laptops", "2.1 km from your location", "Typical rate fits
your ₱1,500 budget". Each is gated on a recorded number crossing a stated
threshold and quotes that number - a 4.8 rating over two jobs is never quoted,
"beats the traffic" is never claimed on clear roads. Caveats (on vacation,
outside their service area, above budget, rated low by you) are listed after
the positives so a recommendation never hides the thing that would change the
client's mind.

The app shows them in the "Why this technician?" sheet. The factor-by-factor
working, rules included, is one tap further ("See how the score was worked
out"), and the whole pipeline - request, context, rules, three stages, Top 3 -
is the **ranking walkthrough**, opened by long-pressing "Based on your current
situation" on the results screen (also a visible link in debug builds).

### Workload-aware ranking

Two candidates whose final scores differ by less than **0.03** are treated as
equally good, and the one with the lighter workload is ranked first. Further
ties break on distance, then rating.

This spreads work across similarly qualified technicians without ever placing a
genuinely worse match above a better one - the epsilon is small enough that a
real quality gap always wins.

### Hard filters

- Unverified technicians never enter the pool.
- Anyone beyond **50 km** is dropped entirely, not merely scored low. No amount
  of skill makes a 60 km call-out sensible, and leaving them in would pad the
  Top 3 with options the client cannot use.
- Below a **0.20** recommendation score, we would rather show fewer than three
  options than three bad ones.

The Top 3 are labelled **Recommended**, **Alternative** and **Another match** -
never "best technician". The ranking knows who fits this request right now,
not who is the better person.

---

## 6. Explainability

Every match card carries a line like:

> Matched because: 5 similar repairs, 2.1km away, available today

Each phrase is derived from a number the engine actually recorded, assembled in
`scoring/rank.ts` and stored in `score_breakdown.explainability`. Tapping the
line opens `ScoreBreakdownSheet`, which renders the whole jsonb: both stages,
every factor with its own score *and* its weight, plus the live conditions at
scoring time.

The weight is shown deliberately. A 90% score on a 10%-weight factor matters far
less than a 60% on a 35% one, and hiding the weight would make the bars
misleading.

### The technician snapshot

`technicians` is readable only by its owner. A client therefore cannot join to
it to display a name or photo. The matcher writes a **snapshot** of the
technician into `score_breakdown.technician` - which the client *can* read
through their own `job_matches` row. Side effect worth mentioning: the card
shows the technician exactly as they were when the match was scored.

---

## 7. The client flow

| Step | Screen | Writes |
| --- | --- | --- |
| 1 | `job_posting_screen.dart` - device, symptom, physical damage | draft only |
| 2 | `guided_classification_screen.dart` - suggested path and why | draft only |
| 3 | `job_detail_input_screen.dart` - location, urgency, budget, schedule, photos | `jobs` insert, then `match-technician` |
| 4 | `client_review_screen.dart` - the Top 3 | reads `job_matches` |

### Classification rules

`ProblemCatalog` in `lib/features/rb_cars/models/problem_catalog.dart` is the
rule base, held as data rather than as branching code so the whole rule set can
be read on one screen. Each symptom carries a path for the intact case and one
for the damaged case, plus an `isAmbiguous` flag.

Routing to the IT community happens in three cases:

1. The client picks **"I am not sure"**.
2. The symptom is **ambiguous** and there is no visible damage, e.g. "will not
   power on" - charger, battery or board, and guessing costs a wasted visit.
3. The symptom code is unrecognised.

All three write `classification_confidence = 'low'`. Everything else writes
`'high'`. The client can override the suggested path, and the override is
recorded, so a rule that is regularly wrong shows up in the data.

---

## 8. Technician confirmation and the decline cascade

Handled by `job-response`.

- **Accept** - fixes it on site. Job becomes `confirmed`, technician assigned,
  workload +1, remaining offers retired.
- **Reroute** - takes it, but it needs the shop. Same as accept, plus the
  service path switches to `pickup`. The honest answer when the on-site
  classification was wrong.
- **Decline** - that row becomes `declined` and the next-ranked live offer is
  promoted. When all three are gone, `runMatching` re-runs with all three
  decliners excluded. Traffic, weather and workloads are all re-read, so the new
  Top 3 is a fresh answer, not a replay.

Confirmation is where RB-CARS ends. Arrival, progress and photo evidence belong
to the tracking module, marked with `TODO(tracking)` in
`job-response/index.ts` and in `technician_confirmation_screen.dart`.

### 7a. The "Recommended technicians" row is not RB-CARS

Worth separating, because the two get confused at a defence.

The row on the client's home screen is a **directory browse**, not a match. It
runs before any job exists, so there is no device, no symptom and no location
to score against - it answers "who is good here?", not "who fits this repair?".
`recommended_technicians` serves it; `match_technicians_for_job` serves the
matching flow. Distance appears on those cards for display only and never
affects their order.

**Who is eligible** (migration `20260921000007`). A technician must have

- **at least 20 completed jobs**, and
- **a review average of 4.0 or better.**

An unreviewed technician has a `NULL` average, and `NULL >= 4.0` is `NULL`, not
true - so twenty *unreviewed* jobs do not qualify. That is deliberate: the rule
is "20 jobs with good reviews", not "20 jobs".

The reasoning is that **"Recommended" is a promise the platform makes in its own
voice.** A client reading that row is being told *we vouch for these people*,
and vouching for somebody with four jobs and one review is a promise the data
cannot keep. The cost of breaking it - a bad first repair, on a recommendation -
lands on the client and on SUGO, not on the technician.

An earlier revision argued against any threshold, on the grounds that it denies
newcomers the one surface that could win them a first job. That was overruled,
and the discovery objection turns out not to hold: **the threshold applies to
this row and nowhere else.** `match_technicians_for_job` still ranks every
technician whose specialisation fits, with no job-count filter at all, and that
is the surface that actually produces bookings. The full ranking below the Top 3
deliberately includes technicians with no history whatsoever.

So the row became a shortlist; matching kept its open door.

When nobody qualifies the row says so - *"Nobody has earned a spot here yet.
Technicians appear once they have completed 20 jobs with good reviews"* - rather
than rendering blank. An empty shortlist is the rule working, and it should read
that way.

**How the eligible are ranked** (migration `20260921000006`). Ordering used to
be rating DESC with job count as a tie-break, which had the classic small-sample
failure: one five-star review outranked 4.8 earned across two hundred jobs.

It ranks on a **Bayesian average** - the same shrinkage IMDb uses - plus a
capped experience term:

```
          v              m
score = ----- * R  +  ----- * C   +   min(ln(1 + jobs) * 0.06, 0.30)
        v + m         v + m

R = their average rating      v = reviews behind it
C = platform mean rating      m = 5 (reviews before a rating stands alone)
```

A rating is trusted in proportion to the evidence behind it; what it is not
trusted for is filled in with the platform average. As `v` grows the score
converges on `R` exactly, so this only ever penalises *absence of evidence* -
never a bad record.

The experience term is logarithmic because 2 jobs versus 20 is a real
difference and 200 versus 220 is noise, and it is capped at +0.30 on a 0-5
scale so volume can break a near-tie but can never lift a mediocre rating over
a strong one.

Within the eligible pool the shrinkage has little left to correct - everyone
there has already cleared 20 jobs, so `v` is large and each score sits close to
its own `R`. It still decides the order among them, and it still stops a lucky
run of five-star reviews from jumping a longer, steadier record.

**Tuning.** Both thresholds are named constants at the top of
`recommended_technicians` (`v_min_jobs`, `v_min_rating`), so changing the bar is
a one-line edit. The migration ends with a query that reports how many
technicians currently clear it - worth running before a demo, because on thin
seed data the honest answer may be zero.

---

### 8a. When nobody answers: the client withdraws

Between `select` and an accept, the client is waiting and there is nothing for
them to do. That window is where the commonest marketplace complaint lives -
*"nobody has answered me"* - and until migration `20260921000003` the only
escape was deleting the whole job and posting it again, losing the device
details, the photos, the location and the ranking already computed.

So the client can now take the request back:

- **On the dashboard**, a job that has been sent names the technician it is
  waiting on, and says how long once the wait passes an hour. Past two hours
  the line turns amber. The name comes from `client_job_technicians`, a view
  over `job_matches` - `jobs.assigned_technician_id` stays null until somebody
  accepts, so the job row genuinely cannot answer "who am I waiting for?".

- **Cancel** calls `withdraw_technician_offer(job_id)` and returns the match to
  `shortlisted`, then reopens the shortlist so they can choose again.

Three decisions worth defending:

1. **It returns to `shortlisted`, not `declined`.** A withdrawal is not a
   refusal. Marking it `declined` would put a decline on the technician's
   record - which feeds `acceptance_score` in Stage 2 - and would drop them
   from the client's own shortlist. Neither is true or fair.

2. **Nothing is recorded against the technician.** A slow answer is not a
   rejection, and the scoring must not learn that it is.

3. **It is an RPC, not an edge-function action.** Every other `job_matches`
   write needs the service role, because it writes outcome history or adjusts
   technician counters. This one reads the caller's own job and flips one row
   on it, touching nothing they cannot already see - so a `SECURITY DEFINER`
   function is the smaller tool, and it keeps the rule beside the policies it
   has to agree with.

The chosen card on the review screen shows *"Request sent — waiting for them to
accept"* instead of a Book button, because `select` refuses a second selection
of the same match. The other two keep their buttons: `select` retires an
outstanding offer before promoting a new one, so switching is genuinely allowed
and this is the screen where a client would want to do it.

---

## 9. Feedback loop

On completion, `job-response` writes one `job_outcomes` row with
`diagnosis_correct`, `rerouted_mid_job` and `final_rating`. Only the client who
posted the job can supply a rating; a technician cannot rate themselves.

`aggregate-outcomes` runs nightly under pg_cron and does two things:

1. **Repairs the denormalised counters.** `technicians.rating` and `total_jobs`
   are caches of what `job_outcomes` already knows. Recomputing them from the
   source of truth makes drift self-healing.
2. **Audits the per-combo accuracy signal.** For every technician x device type
   x problem symptom it reports samples, raw accuracy, smoothed accuracy and how
   far the evidence has moved that combo off the 0.70 prior.

### Why the per-combo signal is computed live, not cached

The schema is fixed at four tables with nowhere to store a per-combo score, so
Stage 1 computes it at match time in one indexed query against `job_outcomes`
filtered to the candidate pool. That has a genuine advantage over a cached
column: an outcome recorded ten minutes ago already influences the next match,
instead of waiting for the nightly run. `aggregate-outcomes` is the audit view
of the same computation - it uses the identical formula, so the two can never
disagree.

If a cache is wanted later, the report rows are already the exact shape a
`technician_accuracy` table would take.

---

## 10. Known limitations

Stating these yourself is stronger than being asked.

| Limitation | Why it is acceptable here | What would fix it |
| --- | --- | --- |
| Distance is straight-line, not road distance | A routing call per technician is N requests per match and blows the free tier. Over a 25 km radius, straight-line ranks candidates in the same order. | TomTom Routing Matrix API |
| Traffic is sampled at the job site only, not per technician | One request instead of N. Congestion at the destination is what determines arrival. | Per-origin flow lookups |
| Weights are hand-set, not learned | No historical data existed to train on at build time. Every weight is a named constant with a written rationale. | Logistic regression on `job_outcomes` once volume exists |
| Hourly fee and years of experience are derived, not stored | `technicians` has no rate or tenure column and the schema is fixed. Derived from tier and `created_at`, documented in `Technician`. | `alter table technicians add column ...` plus one getter |
| Review text is not stored | `job_outcomes` holds a numeric rating only, so the Reviews tab summarises rather than quoting. | A `review_text` column |
| `job-response` reads then writes `current_workload` | Two concurrent accepts could race. Low risk at capstone scale. | A Postgres function doing `set current_workload = current_workload + 1` atomically |
| Rule multipliers are hand-set | Same as the weights: no outcome data to learn them from yet. Each rule carries a written rationale and the cap stops any one from dominating. | Compare acceptance and completion by condition once `job_outcomes` has volume |
| No equipment, rain-gear or errand data | None of it exists in the schema, and inventing it would make the reasons dishonest. | Columns on `technicians`, then one rule each |
| Cancellations are not in the track record | `jobs` does not say who cancelled. | A `cancelled_by` column |
| Client history is per technician only | "Prefers nearby" or "prefers cheaper" would need more bookings per client than a capstone produces. | Learn preferred distance and budget bands from past bookings |

---

## 11. Demo script

1. `npx supabase db push` - creates the four tables.
2. Sign up five accounts in the app.
3. Run `supabase/seed/technicians_demo.sql` - promotes them to technicians,
   including one cold-start and one unverified.
4. `npx supabase secrets set` both API keys, then
   `npx supabase functions deploy`.
5. Post a job: **laptop**, "cracked or blank screen", damage **yes**. Watch the
   rules suggest **shop pickup**.
6. Land on the Top 3. Point out that the unverified technician is absent, and
   that the cold-start technician still made the list.
7. Point at the context chips ("Based on your current situation") and the
   "Ranking adjusted for" line. Tap **Why this technician?** on a card for the
   client's view, then **See how the score was worked out** for all three
   stages. Long-press the chips to open the **ranking walkthrough** and walk the
   panel through request, context, rules, Stage 1, Stage 2, recommendation and
   Top 3.
7a. Post the same job with **Need it today** and show the "Needed today" rule
   fire and the distance/availability weights move in the breakdown.
8. Decline as rank 1. Show rank 2 being promoted. Decline all three and show the
   re-match with everyone excluded.
9. Complete a job with `diagnosis_correct = false`. Re-run the match and show
   that technician's accuracy factor has moved.
