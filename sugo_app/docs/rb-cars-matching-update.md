# RB-CARS matching: registration-aware Stage 1 and Stage 2

How the matcher changed once registration started capturing identity, brands,
assessed skill levels, base locations and client trust.

Everything below extends the existing engine in
`supabase/functions/match-technician/scoring/`. No parallel matcher was added.

---

## Two schema gaps that had to be closed first

`20260907000010_matching_inputs.sql`.

### 1. A job had no brand

`technician_specializations` records `(device_type, brand)`. `jobs` recorded no
brand at all, so "match the technician's brand to the job's brand" had nothing
to compare against. `jobs.brand` was added, plus a picker on the job posting
screen — without a way to *enter* a brand, the whole ladder would have been
dead code.

### 2. The two device vocabularies did not overlap

This is the one that would have silently returned zero matches.

```
jobs.device_type                        laptop | phone | appliance | network
technician_specializations.device_type  laptop, desktop, smartphone, tablet,
                                        printer, aircon, refrigerator,
                                        washing_machine, television, microwave
```

An equality test between them matches only the literal word `laptop`. Every
desktop, aircon and washing-machine technician would have been excluded from
every job, with nothing anywhere to explain why.

`jobs.device_type` is part of the frozen RB-CARS four-table schema and the
accuracy index is keyed on it, so it was left alone. A nullable
`jobs.device_detail` carries the precise device, and
`job_device_candidates(device_type, device_detail)` maps the coarse value onto
the set of fine ones when it is absent. Old jobs keep matching; new ones can be
exact.

**Known gap:** `printer` belongs to no coarse category, so a printer job can
only be matched precisely by setting `device_detail`.

---

## Stage 1 — Suitability

### Hard filters, applied before anything is scored

In `engine.ts`. All exclude rather than penalise.

| Gate | Rule |
|---|---|
| `is_verified` | Permanent, set by SUGO. Allowed to work at all? |
| `is_available` | The technician's own switch. Taking jobs now? |
| **`identity_approved`** | A human approved their ID + selfie |
| **service radius** | distance(job, technician base) <= `service_radius_km` |

**Why the identity gate is not redundant with `is_verified`.** They move
together today, because `activate_account()` sets both. But they mean different
things — "cleared to work" and "we know who this is" — and an unverified
identity must never reach a client's doorstep because some future change moved
one flag without the other. Cheap to assert, catastrophic to assume.

**Why the radius is a filter, not a score.** The technician told us they will
not travel that far. Offering anyway wastes a Top 3 slot on someone who will
decline, and the `job-response` cascade then has to run again. A second
absolute ceiling (`HARD_RADIUS_KM`) still applies, so a technician who typed
100 km is not sent across a province.

### The brand + device ladder

`specializationMatchScore()` in `suitability.ts`. Now the heaviest Stage 1
factor at weight **0.35**, up from 0.25, because an assessed brand-level claim
is much stronger evidence than a self-typed skill tag.

| Rung | Condition | Score |
|---|---|---|
| **a** | Assessed **Expert** on this exact brand **and** device | 1.00 |
| **b** | Assessed **Intermediate** on this exact brand and device | 0.85 |
| **c** | Assessed Expert on the device, different brand | 0.70 |
| **c** | Assessed Intermediate on the device, different brand | 0.60 |
| **d** | Declared but never assessed, on this brand or device | 0.35 |
| — | Legacy `technicians.specialization` array only | 0.30 |
| — | Nothing matches | 0.10 |

**Nothing is filtered out.** A self-claimed specialisation is weak evidence,
not disqualifying evidence — and a client whose exact brand nobody has been
assessed on still needs three names. Rung (d) ranks last instead of vanishing.

**"Others" or a blank brand skips the brand filter.** Insisting on a brand
match would exclude everybody on a technicality the client never expressed, so
the ladder degrades to device-only.

### Verification tier — the secondary sort key

`basic` 0.55 → `verified` 0.80 → `certified_pro` 1.00, at weight **0.18**.

This **replaced a boolean `verified` factor**. Identity approval is now a hard
gate, so that boolean was 1 for every candidate that reached scoring — it spent
0.15 of the weight budget telling the ranking nothing at all. The tier
distinguishes candidates the boolean could not.

`basic` is not zero: identity was still approved by a human. The tier only says
how much *extra* paperwork was checked.

---

## Stage 2 — Acceptance

Budget, workload, urgency/path, traffic and weather are unchanged. Two
additions.

### Client trust (weight 0.10)

A no-show costs a technician a round trip across the city and a slot they could
have sold, so who is asking is part of "will they take this job?".

| Trust level | Score |
|---|---|
| `new` | 0.70 |
| `verified` | 0.90 |
| `trusted` | 1.00 |

Minus 0.08 per recorded no-show, capped at 0.30.

**Soft, never a block, and the floor is high on purpose.** Every client starts
at `new`. A harsh penalty would be a cold-start trap on the client side — the
people the platform most needs to attract would be hardest to match, and would
never earn the completed jobs that raise their trust level. At weight 0.10 the
worst case moves the final score about two points in a hundred: enough to break
a tie, never enough to leave someone unable to book. The remedy for a genuine
repeat no-show is an account action by a human.

### Distance and ETA from the real base location

Ranking used `technicians.latitude` — a *working* position that is null for
anyone not currently on a job and stale for anyone who just finished one. A
technician who had never worked had no distance at all.

Now distance, the radius gate and the ETA all come from
`base_latitude`/`base_longitude`, captured during registration. The live
position is still carried in the snapshot for the tracking map; it is simply
not what ranking is based on. `context.measured_from` records which was used.

---

## Verified

### Unit — the ladder and trust rules

```sh
cd supabase/functions/match-technician/scoring
node --experimental-strip-types matching_rules.test.ts
```

16 assertions covering every rung, the "Others" fallback, the desktop-to-laptop
bridge, the ordering property that exact-brand Intermediate beats device-only
Expert, and the no-show cap. All pass.

### End to end — against the live deployment

A temporary fixture (a laptop/Apple job, an approved technician assessed Expert
on laptop/Apple), invoked through the deployed `match-technician`, then removed
entirely:

```
rank 1 | final 0.8272 | stage1 0.825 | stage2 0.8305
explain: assessed on Apple - Certified Pro - 126m away - light schedule today
  specialization      1.00   Assessed Expert on Apple laptop
  verification_tier   1.00   Certified Pro
  client_trust        0.70   New client, no booking history yet
  ctx measured_from=base_location radius=15 matched=[laptop/Apple]
```

Gates, each toggled and re-run:

| Test | Result |
|---|---|
| Identity set to `rejected` | `evaluated=0` — excluded |
| Identity back to `approved` | `evaluated=1` |
| Job moved ~48 km away (radius 15) | `evaluated=0` — "outside their own service radius" |
| Radius raised to 60 | `evaluated=1` |
| Job brand changed to Dell | specialization drops 1.00 to 0.70, "not on Dell specifically" |

The fixture was fully torn down and the client's password hash restored byte
for byte.

### Contract

`test/features/rb_cars/device_brand_picker_test.dart` pins the Flutter device
list to `job_device_candidates()` in SQL. If the two ever diverge, a job would
carry a `device_detail` the matcher cannot use, and Stage 1 would return nobody
with no error to explain it.

---

## Limitations

1. **`printer` is unreachable from a coarse category.** A printer job posted
   without `device_detail` matches computer technicians.
2. **Brand matching is exact-string, case-insensitive.** "Samsung" and
   "Samsung Electronics" are different brands to the matcher. Both sides pick
   from the same `SpecializationCatalog`, which is what keeps them aligned, but
   a technician's free-text "Others" brand will rarely match a client's.
3. **Straight-line distance, not road distance.** Unchanged, and still the
   right trade — a routing call per technician would be N requests per match.
4. **Client trust has no decay.** A no-show from a year ago counts as much as
   one from last week.
