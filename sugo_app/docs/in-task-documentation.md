# In-task documentation: the work record

Built 2026-11-22. Covers **Specific Objective 4** ("a booking and workflow
tracking system with in-task documentation") and **FR-11** ("timestamped
photos, text updates, and location stamps during a task as proof of service
delivery"). Migration `20261122000002_job_evidence.sql`.

## What it does

During a job the technician photographs fixed checkpoints. Each photo set is
saved with the **server's time** and the **phone's GPS**, and **cannot be
edited or deleted** afterwards. The technician **cannot mark the job complete**
until the two required checkpoints exist. The client sees the photos as a
**Work record** on the booking, and the admin sees them beside any dispute.

## Checkpoints

| Step (`milestone`) | Home Service | Shop Repair (pickup) | Shop Repair (drop-off) | Required |
| --- | --- | --- | --- | --- |
| `intake` | **Before** | **Collected** | **Unit received** | Yes |
| `diagnosis` | Diagnosis | Diagnosis | Diagnosis | No |
| `progress` | Progress | Progress | Progress | No |
| `after` | **After** | **After repair** | **After repair** | Yes |
| `handover` | (none) | Handover | Handover | No |

1–4 photos per step, an optional note (up to 500 characters). "After" can only
be added once the unit-as-found step exists. Photos are taken with the camera;
the gallery is not offered, because a gallery picture could be from any day.

## The rules, and where each is enforced

| Rule | Enforced in |
| --- | --- |
| Only the assigned technician adds photos, only while the job is confirmed or in progress | `add_job_evidence()` and the `job-evidence` storage policy |
| Photos must sit in this job's folder (`<job_id>/...`) | `add_job_evidence()` |
| "After" needs the unit-as-found step first | `add_job_evidence()` |
| The time cannot be faked | `captured_at` defaults to `now()` in the database |
| Records are never changed or deleted | No update or delete policy on the table or the bucket |
| The job cannot be completed without Before and After | `job-response` calls `job_evidence_missing()` and refuses with 409 |
| Only the client and the technician on the job can see the photos | Table RLS and the storage read policy; the admin uses the service role |
| Jobs posted before the feature are exempt | `job_evidence_cutoff()`, frozen to the moment the migration ran |

The completion check runs on the server, so an old app build cannot skip it.
It applies when the technician completes the job; a client closing the job is
not held to it.

## Screens

* **Technician, on a job under way:** a checklist under "Your job". Each step
  shows what to photograph, a *Required* tag until it is done, and a camera
  button. "Mark as complete" is disabled with "Add the Before and After photos
  first" until both exist.
* **Client:** a *Work record* card on the booking, folded to one line ("Before
  · After", or "No photos yet") like the page's other secondary sections. Open,
  it shows each step's photos, the time, "At the job address" / "2.4 km from
  the job address" / "Location not recorded", and the note.
* **Admin, Disputes:** each report shows the booking's work record: the steps,
  times, a GPS link, notes and photos.

## Files

| Part | File |
| --- | --- |
| Table, functions, bucket, policies | `supabase/migrations/20261122000002_job_evidence.sql` |
| SQL tests (34 checks, PGlite) | `tool/sql_tests/trust_badge/job_evidence.mjs` (`npm run test:job-evidence`) |
| Completion check | `supabase/functions/job-response/index.ts` (`handleComplete`) |
| Refusal wording | `supabase/functions/_shared/evidence.ts` (+ `evidence.test.ts`) |
| App model, service, widgets | `lib/features/evidence/` |
| Screen wiring | `lib/features/bookings/screens/job_detail_screen.dart` |
| App tests | `test/features/evidence/work_record_test.dart` |
| Admin | `sugo-admin/app/Http/Controllers/DisputeController.php`, `resources/views/disputes/index.blade.php` |

## Deploying, in this order

1. `npx --no-install supabase db push --remote` - the table, the bucket and
   the functions. The cutoff is set at this moment.
2. Deploy `job-response` (the completion check). Until it is deployed, the
   app still blocks "Mark as complete", but the server does not.
3. Rebuild the app. An app built before this has no camera checklist, so its
   technicians would be refused at completion once step 2 is live - ship the
   new build to technicians before, or together with, step 2.
