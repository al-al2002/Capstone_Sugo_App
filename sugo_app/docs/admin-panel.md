# SUGO review console (Laravel admin)

The web panel where a human approves or rejects the government ID + selfie that
every SUGO account must submit. Lives in `sugo_app/sugo-admin/`.

---

## Running it

```sh
cd sugo_app/sugo-admin
php artisan serve
```

Then open <http://localhost:8000> and sign in.

| | |
|---|---|
| Email | `admin@sugo.ph` |
| Password | `admin123` |

No `npm install`, no `npm run build`, no database to migrate. Tailwind loads
from its CDN and there is no local database at all — see below.

---

## There is no local database

The panel's only data store is Supabase. That was a deliberate instruction and
it shapes everything:

- **Sign-in** goes to Supabase Auth (`/auth/v1/token`), the same endpoint the
  Flutter app uses.
- **Every row shown** is fetched from Supabase over HTTP (PostgREST).
- **Every decision** is written by calling a Postgres function (`/rest/v1/rpc/`).

`.env` therefore sets `SESSION_DRIVER=file`, `CACHE_STORE=file` and
`QUEUE_CONNECTION=sync`, so nothing reaches for SQLite. The `database.sqlite`
file left over from the Laravel skeleton is unused.

The admin account is a `profiles` row like anybody else's, with
`role = 'admin'`. It is not a separate users table, because
`identity_verifications.reviewed_by` already references `profiles(id)` — a
separate admin table would mean a foreign key pointing at two different places
for the same column.

---

## Two keys, two jobs

`sugo-admin/.env` holds both Supabase keys, and the difference matters.

| Key | Used for | Power |
|---|---|---|
| `SUPABASE_ANON_KEY` | The sign-in call | None on its own — every table is behind RLS |
| `SUPABASE_SERVICE_ROLE_KEY` | Everything else | **Bypasses every RLS policy** |

The service role key is what lets a reviewer open somebody else's identity
document. No ordinary session can: `identity_verifications` is restricted to
`user_id = auth.uid()`. That power is the reason the console works and the
reason the key must never leave the server — it is read in PHP, sent in a
server-to-server header, and never passed to a Blade view.

`.env` is gitignored. If you ever need to re-fetch the keys:

```sh
npx supabase projects api-keys --project-ref nlchvhygejurjvuyluwe
```

---

## Authorisation: two checks, both required

`Supabase::signInAdmin()` does this, in order:

1. **Supabase Auth accepts the password.** Proves the credential.
2. **The matching `profiles` row has `role = 'admin'`.** Proves authorisation.

Step 2 is not optional decoration. A technician's or client's own login is a
perfectly valid credential on the same Auth instance — step 1 would pass for
them. Step 2 is the only thing keeping them out of a console that can read
every ID on the platform.

This was tested rather than assumed: with the admin account temporarily
demoted to `role = 'client'`, the **correct** password was refused. Restoring
the role restored access.

Beyond that:

- Every route except sign-in is behind the `EnsureAdmin` middleware, applied to
  the route *group* so a new screen cannot be added without it.
- Sign-in is rate limited to 5 attempts per minute per email + IP.
  `admin@sugo.ph` is not a hard address to guess.
- One error message covers a wrong password, an unknown address and a valid
  non-admin account alike, so the form cannot be used to discover which emails
  have accounts.

---

## The screens

| Route | What it does |
|---|---|
| `/` | Dashboard — counters, the oldest waiting submissions, recent decisions |
| `/verifications` | The ID queue, filterable by pending / approved / rejected |
| `/verifications/{id}` | **The review screen.** Both photos side by side, applicant detail, previous attempts, approve/reject |
| `/documents` | Optional credentials — certificates, NBI clearances, portfolio |
| `/accounts/technician`, `/accounts/client` | Browse accounts and their standing |

### The review screen

The two images are shown side by side because that is the actual judgement:
does the face in the selfie match the face on the ID, and is the ID in the
selfie the same document. Each opens full size in a new tab, since detail on an
ID is usually unreadable at card size.

Images load through **signed URLs that expire in 10 minutes**. The bucket is
private, so this is the only way to render them, and a link left in browser
history is dead well before anyone could reuse it. If an image fails to sign,
the panel says so rather than showing a blank frame — never approve a
submission you could not see.

A repeat applicant is flagged at the top with their attempt number and every
previous rejection reason, because a third submission is a different judgement
call from a first.

### What approving actually does

The console never writes to a table directly. It calls
`review_identity_verification()`, which holds rules a direct write would skip:

- **A rejection must carry a reason.** The database refuses one without it, and
  so does the form. The applicant is shown that text word for word, so write
  what they should change — not an internal note.
- **Approving does not always activate.** If the person has already submitted
  their whole registration, they go live immediately. If they are still
  mid-flow, their ID is marked approved and the account status is left alone so
  they can carry on; the final submit then activates them with no second
  review. Whichever of the two finishes second is what turns the account on.
- **A technician's `is_verified` is set only when both conditions hold** —
  identity approved *and* at least one assessment passed. That flag is what
  admits them to the RB-CARS matching pool.

Read-only is deliberate everywhere else. There is no "edit account" screen:
activation, verification tier and trust level are consequences of a review
decision, enforced by database functions. An editable field would be a way
around all of it.

---

## Setup notes and gotchas

### The admin user is created by migration, not by hand

`20260907000006_admin_role.sql` inserts it directly into `auth.users` with a
bcrypt hash, so the whole thing is reproducible from `supabase db push` with no
out-of-band step. Re-running the migration resets the password, so a forgotten
demo password is one `db push` away from working again.

### "Database error querying schema" on sign-in

If you ever hand-create another Supabase user and it exists but cannot log in
with a 500, this is why. `auth.users` has eight token columns that Postgres
marks nullable but GoTrue scans into non-nullable Go strings:

```
confirmation_token   recovery_token   email_change   email_change_token_new
email_change_token_current   phone_change   phone_change_token
reauthentication_token
```

They must be `''`, never `NULL`. A row created by the Auth admin API always
writes `''`; a hand-written INSERT leaves NULL and every sign-in for that
account then fails inside GoTrue's row scan. The 500 names neither the column
nor the row, which is what makes it hard to place. `20260907000007` repairs it
and `20260907000006` now writes them correctly.

---

## Known limitations

Name these first rather than being asked.

1. **The password is `admin123` and it is in the repository.** Acceptable for a
   capstone demonstration and nothing else. To change it:
   ```sql
   update auth.users
   set encrypted_password = extensions.crypt('a better password', extensions.gen_salt('bf'))
   where email = 'admin@sugo.ph';
   ```

2. **Anyone with the `.env` has full read access to every identity document.**
   The service role key bypasses RLS by design. Protect that file the way you
   would protect a database password.

3. **There is one admin account and no roles within the console.** Any admin
   can approve anything. A real deployment would want at least a
   reviewer/superadmin split and a way to add admins from the UI rather than
   from SQL.

4. **No audit log beyond the review columns.** `reviewed_by`, `reviewed_at` and
   `admin_notes` record who decided what and why, which covers the decisions
   themselves — but not who *looked* at an identity document without acting.
   For real personal data, viewing should be logged too.

5. **Tailwind loads from a CDN.** No build step, but the page needs the network
   to style itself and there is no offline mode. The Vite pipeline is already
   configured in this project if that becomes a problem.

6. **Sessions are files on disk.** Fine for one machine; a multi-server
   deployment would need a shared session store.

---

## Verified

Checked against the live project, not assumed:

- Login as `admin@sugo.ph` → dashboard, rendering real Supabase counters
- Wrong password → refused
- Correct password with `role` demoted to `client` → **refused**
- All five screens return HTTP 200 with no PHP errors
- Both signed image URLs on the review screen resolve to real images
- Rejecting with no reason → refused, and the submission stayed `pending`
- Signed-out requests to `/` and `/verifications` → redirected to `/login`
