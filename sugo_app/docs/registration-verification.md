# Registration with mandatory ID verification

Everything here is run from the `sugo_app/` folder, the one containing
`supabase/`.

This covers the technician and client registration flows, the mandatory
government ID + selfie check that both go through, and the admin review that
decides whether an account goes live.

---

## The one-paragraph version

Both roles now register through a stepper whose second step is a government ID
plus a selfie holding that ID. Neither can be skipped. Everything the user does
is saved as they go, so they can leave and resume. When the required steps are
done the account moves to `pending_review`, and a human at SUGO approves or
rejects it. Only that approval makes an account `active`.

---

## 1. The account status machine

`profiles.registration_status` is the single source of truth for what an
account may do.

```
                  sign up
                     │
                     ▼
              ┌─────────────┐
              │ incomplete  │  ◄──────────────┐
              └─────────────┘                 │
                     │                        │
        submits ID + selfie + the rest        │
                     │                        │
                     ▼                        │
              ┌─────────────┐                 │
              │pending_review│                │
              └─────────────┘                 │
                  │       │                   │
         approved │       │ rejected          │
                  ▼       ▼                   │
            ┌────────┐  ┌──────────┐          │
            │ active │  │ rejected │──────────┘
            └────────┘  └──────────┘   retake photos
```

Note the diagonal: an account can also go **`incomplete → active` directly**.
That happens when a reviewer approves the ID while the user is still working
through the later steps — see section 2a.

**A user can only ever make one of these transitions themselves:**
`incomplete → pending_review`. Everything else requires the service role.

That is enforced twice, deliberately:

- `guard_registration_status()`, a trigger on `profiles`, rejects any other
  self-transition. It exists because `profiles` has had an owner-update policy
  since the very first migration, and RLS filters *rows*, not *columns* — so
  without the trigger any user could run
  `update profiles set registration_status = 'active' where id = auth.uid()`
  and approve their own identity documents.
- `submit_registration_for_review()` is `service_role` only, so even the one
  permitted transition happens through a function that checks nothing required
  is missing.

**This is the thing to say out loud at defence:** the app asks; the server
decides. An account can never certify itself.

---

## 2. What changed from the previous design, and why

Migration `20260906000006_defer_profile_creation.sql` had made registration
all-or-nothing. The sign-up trigger was dropped, nothing was written to the
`public` schema until the whole flow committed, and the documented consequence
was that **a half-finished registration could not be resumed**.

`20260907000001_registration_status.sql` reverses that. Two things forced it:

1. The flow is now long — up to seven steps for a technician — and ends in a
   human review queue rather than an instant pass. Making someone redo all of
   it because their phone rang is not defensible.
2. The brief requires an explicit `incomplete` account status, which an absent
   row cannot express.

**The cost, stated plainly.** An abandoned registration now leaves rows behind
where previously it left none. They are labelled rather than absent, and
`purge-abandoned-signups` still sweeps them — it just looks for
`registration_status = 'incomplete'` instead of "no profile row". The trade
accepted was: resumability is worth more than a `public` schema that stays
empty until commit.

Two knock-on changes came from the same decision:

- **Passing an assessment no longer activates an account.** It used to set
  `is_verified = true` directly, with a TODO in `submit-assessment` saying a
  human should check the ID first. That TODO is now resolved. A quiz measures
  competence, not identity.
- **`SessionProfile.destination` reads the status before the role.** Before,
  merely having a profile row proved registration was finished. Now it does
  not, and routing on role alone would send every brand-new signup straight to
  a dashboard. There is a regression test for exactly this in
  `test/features/onboarding/registration_gate_test.dart`.

---

## 2a. Review runs in parallel with the rest of the flow

The ID step sits second so it cannot be skipped, but a reviewer may take hours
and the later steps have nothing to do with identity. So the user is **not**
blocked: the Continue button stays live on the ID step once a submission is
filed, and they carry on with specialisations, the assessment, documents and
location while review happens.

That makes identity approval and registration completeness two independent
conditions. **An account goes live when both hold, and whichever happens second
activates it.**

| Order of events | What happens |
|---|---|
| Approval first, submit second | Approval leaves the status alone; the final submit activates directly, with no second review |
| Submit first, approval second | Submit sets `pending_review`; the approval activates |

Both paths end in `activate_account()`, so the rule exists once rather than
twice.

`20260907000005_review_during_flow.sql` added this, and it fixed two real bugs
that were confirmed against the live database first:

- **Approving mid-flow used to set `pending_review`**, which routes to the
  waiting screen — so a reviewer doing their job promptly would lock a
  technician out of finishing their own assessment.
- **Nothing ever set `technicians.is_verified`.** `submit-assessment` stopped
  setting it (correctly — a quiz does not prove identity) and no replacement
  existed, so an approved technician could never reach the dashboard.
  `activate_account()` now owns that flag, and only sets it when identity is
  approved *and* an assessment has been passed.

---

## 2b. One assessment per skill, not per brand

A specialisation is a (device, brand) pair, so a technician who repairs laptops
and desktops for Apple, Dell and HP declares **six** of them. Originally each
needed its own assessment — and the question bank never differed by brand, so
they would have answered the identical ten questions six times.

`20260907000008` groups competence into **tracks**. Passing one verifies every
specialisation inside it.

| Track | Devices |
|---|---|
| `computer_repair` | laptop, desktop |
| `mobile_repair` | smartphone, tablet |
| `printer_repair` | printer |
| `refrigeration` | aircon, refrigerator |
| `laundry_appliance` | washing machine |
| `home_electronics` | television, microwave |

Worst case falls from 10 devices × 7 brands = **70 assessments to 6**.

**Brand is deliberately not assessed.** What is being measured is whether
someone can diagnose a compressor or a dead mainboard, and that does not change
between Samsung and LG. Brand still matters for *matching* — it is what pairs a
client's LG aircon with a technician who declared LG — but testing it would be
brand trivia, not skill.

This also fixed a dead end. Only `appliance_repair` was ever seeded, so
`laptop_repair` and `phone_repair` had no questions at all: a laptop technician
could never pass anything, never satisfy `submit_registration_for_review()`,
and never finish registering. All six tracks now have ten questions each.

The mapping lives in `public.assessment_track()` and is mirrored by
`AssessmentTrack` in the Flutter catalogue so the UI can group without a round
trip. A test pins the two copies together.

### Editing the list afterwards

Grouping created a second problem, fixed by `20260907000009`. Because one pass
verifies every brand in a track, a technician who passed `computer_repair`
after mistakenly adding "Desktop / MSI" could never remove it — the delete
policy only allowed unverified rows.

That restriction existed to protect the attempt history:
`technician_assessment_results.specialization_id` was `not null on delete
cascade`, so deleting the specialisation erased the attempts, and a technician
could have dodged the 24-hour cooldown by deleting and re-adding.

Since attempts are keyed on `track`, the pointer no longer needs to be
load-bearing. It is now nullable with `on delete set null`, so:

- **any of your own specialisations can be removed**, verified or not
- **the attempt history and the cooldown survive** the deletion
- **re-adding a brand in a track you already passed comes back verified**, via
  the `inherit_track_verification` trigger — otherwise it would be stranded
  permanently unproven, since re-sitting a passed track is refused

Verified live, end to end: one pass verified 9 computer rows and left
`printer/Epson` alone; removing a verified brand kept the attempt row; re-adding
it returned `verified=true, level=expert` with no retake; and re-sitting the
passed track was still refused.

Verified live: 7 specialisations across laptop, desktop and aircon resolved to
2 tracks, and one `computer_repair` pass verified all 6 laptop/desktop rows
while correctly leaving `aircon/LG` unverified.

---

## 3. Run the migrations

```sh
supabase db push
```

That applies, in order:

| Migration | What it adds |
|---|---|
| `20260907000001_registration_status.sql` | `registration_status` + `registration_step` on `profiles`, restores the sign-up trigger, the self-transition guard, rebuilds `incomplete_signups` |
| `20260907000002_identity_verifications.sql` | `identity_verifications`, the review function, the reviewer queue view |
| `20260907000003_technician_registration.sql` | `technician_specializations`, `technician_assessment_results`, `technician_verification_documents`, the base-location columns |
| `20260907000004_client_registration.sql` | `client_verification_status`, `client_saved_addresses`, `phone_verifications`, `submit_registration_for_review()` |
| `20260907000005_review_during_flow.sql` | `activate_account()`; lets review run in parallel and finally sets `is_verified` |
| `20260907000006_admin_role.sql` | The `admin` role, the console's account, and the reviewer views |
| `20260907000007_fix_auth_null_tokens.sql` | Repairs NULL token columns that break GoTrue sign-in |
| `20260907000008_assessment_tracks.sql` | Assessment tracks — one quiz per skill, not per brand — plus a question bank for every track |
| `20260907000009_editable_specializations.sql` | Lets a technician remove a verified specialisation without losing attempt history |

Migration 1 backfills two things, so existing accounts are not locked out:

- every account with `onboarding_completed_at` set is marked `active`
- every `auth.users` row orphaned while deferred creation was in force gets a
  profile

### Check it applied

```sql
-- Should list four statuses and their counts.
select registration_status, count(*) from profiles group by 1;

-- Should return one row per new table.
select tablename from pg_tables
where schemaname = 'public'
  and tablename in (
    'identity_verifications', 'technician_specializations',
    'technician_assessment_results', 'technician_verification_documents',
    'client_verification_status', 'client_saved_addresses',
    'phone_verifications'
  );
```

---

## 4. Deploy the edge functions

```sh
supabase functions deploy submit-registration
supabase functions deploy send-phone-code
supabase functions deploy verify-phone-code
supabase functions deploy submit-assessment   # updated, redeploy it
```

`submit-assessment` **must** be redeployed — it is what stopped auto-verifying
accounts. Leaving the old copy live means technicians still activate themselves
by passing a quiz, which defeats the whole feature.

---

## 5. Storage

No new bucket. Selfies go in the existing private `identity-documents` bucket
from `20260906000004`, because a selfie holding a government ID is exactly as
sensitive as the ID itself — same document, plus a face.

Migration 2 raises that bucket's cap from 5 MB to 10 MB, since a camera selfie
is larger than a scanned document.

Nothing about an identity document is readable from a guessable URL. The bucket
is private and the app mints a five-minute signed URL when it needs to show one
back to the user.

---

## 6. Reviewing an account

Read the queue:

```sql
select * from identity_review_queue;
```

It gives the applicant, both object paths, how long they have been waiting, and
their attempt number — so a reviewer can see this is someone's third try and
read why the first two failed.

Approve or reject:

```sql
-- Approve
select review_identity_verification(
  '<verification_id>'::uuid, true, '<reviewer_profile_id>'::uuid, null
);

-- Reject. The note is REQUIRED and is shown to the applicant verbatim.
select review_identity_verification(
  '<verification_id>'::uuid, false, '<reviewer_profile_id>'::uuid,
  'The ID in your selfie is not readable. Please retake it in better light.'
);
```

A rejection with no reason is refused by the function. A generic "rejected"
gives the applicant nothing to change, so they resubmit the same photos and are
rejected again — which is how a review queue fills up with the same person
three times.

What approval does depends on how much else is finished:

- **Account already `pending_review`** — everything else was validated at
  submit, so approval is the last condition. The account goes `active`, and a
  technician gets `is_verified = true` plus a `verification_tier` of `verified`
  (or `certified_pro` if they have an approved certificate or NBI clearance).
- **Account still `incomplete`** — the verification row is marked approved but
  the account status is deliberately left alone, so the user keeps working
  through the remaining steps. Their final submit activates them without
  needing a second review.

---

## 7. Known limitations

Worth naming these first rather than being asked.

1. **No automated identity checking.** The app confirms two images of a
   plausible size and format were supplied. It cannot tell whether the face in
   the selfie matches the ID, or whether the ID is real. That judgement is
   entirely the human reviewer's. A production system would pre-screen with a
   face-match API and document OCR so the queue only sees genuine judgement
   calls. See the TODO in `IdentityVerificationService.submit`.

2. **No SMS provider.** `send-phone-code` generates a real code with a CSPRNG,
   stores it with a ten-minute expiry, invalidates the previous one, and never
   lets the client read it. What is missing is the call to a gateway. While
   `SMS_PROVIDER` is unset the function returns the code in `debug_code` so the
   flow is testable; set that variable and implement `sendSms()` before any
   real deployment.

3. **Assessment questions are placeholders.** Every track is seeded with ten
   questions, so no device is a dead end — but a real deployment would have
   them written and reviewed by working technicians. They are not fake: each
   has a single defensible answer from ordinary repair practice. The UI, the
   scoring, the bands, the attempt numbering and the retake cooldown are all
   real.

4. **Nominatim is called directly from the app.** Its usage policy limits you
   to roughly one request per second per IP, which the debounce and the
   in-service rate limiter respect. But the limit is *per IP*, and on a mobile
   network many users share one carrier NAT address — so they can collectively
   exceed it while each behaves perfectly. Moving the calls behind an edge
   function with a cache, or self-hosting Nominatim, is the real answer at
   scale.

5. **The OTP code is stored in plain text.** Deliberate: it is a six-digit
   number valid for ten minutes, and anyone who can read that table already has
   the service role and could set `phone_verified` directly. Hashing it would
   protect against nothing that is not already lost.

---

## 8. Where the code lives

```
lib/features/onboarding/
  models/         status machine, identity capture, specialisation catalogue
  services/       identity, technician, client, geocoding
  controllers/    registration_flow_controller.dart  ← the shared gate
                  technician_registration_controller.dart
                  client_registration_controller.dart
  widgets/        id_verification_step.dart          ← used by BOTH flows
                  onboarding_stepper.dart, location_pin_step.dart,
                  specialization_picker.dart, onboarding_scaffold.dart
  screens/        registration_entry_screen.dart     ← role choice, then hands off
                  technician_registration_screen.dart
                  client_registration_screen.dart
                  assessment_screen.dart, verification_documents_step.dart
```

Two files carry most of the argument:

- `widgets/id_verification_step.dart` is built once and used by both flows.
  That is the code-level expression of "both roles face the same check" — there
  is one implementation, so the two cannot drift apart.
- `controllers/registration_flow_controller.dart` holds `canLeaveIdentityStep`.
  The Continue button, the progress rail's forward navigation and the final
  submit all consult that one getter, which is why there is no path around the
  gate.
