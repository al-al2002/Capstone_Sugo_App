# Supabase Edge Functions setup

Everything here is run from the `sugo_app/` folder, the one containing
`supabase/`.

## What an edge function actually is

A Deno TypeScript program that Supabase runs for you, on their infrastructure,
in response to an HTTP request. Three properties matter for RB-CARS:

1. **It holds secrets.** `Deno.env.get('TOMTOM_API_KEY')` works there and
   nowhere in the Flutter app.
2. **It can bypass RLS.** Supabase injects `SUPABASE_SERVICE_ROLE_KEY` into
   every function. A client built with that key ignores every policy, which is
   exactly what the matcher needs: it must read *all* technicians to rank them,
   while the `technicians_select_own` policy allows a normal user to read only
   their own row.
3. **The client calls it with its own JWT.** `supabase.functions.invoke()` sends
   the signed-in user's access token in the `Authorization` header, so the
   function can verify *who* is asking before it uses its elevated powers.

Point 3 is the security seam and the thing to say out loud at defence: the
function is powerful, so every one of ours re-checks the caller's identity
against the row it is about to touch. Elevated privilege plus an explicit
ownership check, never elevated privilege alone.

---

## 1. Install the CLI

The Supabase CLI is not installed on this machine yet. On Windows, pick one:

**Option A - Scoop (recommended, gives you a real `supabase` command)**

```powershell
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

**Option B - no install, run through npx**

```sh
npx -y supabase@latest --version
```

Verified working on this machine: it printed `2.116.0`.

Two things to expect. The **first** run downloads the CLI and took over seven
minutes here; every run after that is served from the npx cache and takes about
five seconds. And the `-y` flag skips the "Ok to proceed?" prompt, which
otherwise hangs any non-interactive shell.

Every command below is written with `npx supabase`. If you installed via Scoop,
drop the `npx` prefix. Do **not** `npm install -g supabase`; the CLI is
explicitly not supported as a global npm package.

---

## 2. Log in and link the project

```sh
npx supabase login
```

That opens a browser and stores an access token on your machine.

```sh
npx supabase link --project-ref nlchvhygejurjvuyluwe
```

The project ref is the subdomain in your Supabase URL
(`https://nlchvhygejurjvuyluwe.supabase.co`). It will ask for the database
password, which is the one set when the project was created. Linking writes
`supabase/.temp/` and lets `db push`, `secrets` and `functions deploy` all
target the right project without repeating the ref.

Confirm the link:

```sh
npx supabase projects list
```

The linked project shows a bullet in the `LINKED` column.

---

## 3. Apply the RB-CARS migration

```sh
npx supabase db push
```

This runs every file in `supabase/migrations/` that the remote database has not
seen, in filename order. It will report:

```
Applying migration 20260905000001_rb_cars_schema.sql...
Finished supabase db push.
```

`20260904000001_create_profiles.sql` is skipped if you already ran it by hand in
the SQL Editor — but only if the CLI knows about it. If `db push` tries to
re-run the profiles migration and fails on "relation already exists", mark it as
already applied:

```sh
npx supabase migration repair --status applied 20260904000001
```

then run `db push` again.

**Verify in the dashboard.** Open your project, then **Table Editor**. In the
`public` schema you should now see five tables:

| Table | Rows | Meaning |
| --- | --- | --- |
| `profiles` | your existing accounts | unchanged, still there |
| `technicians` | 0 | new |
| `jobs` | 0 | new |
| `job_matches` | 0 | new |
| `job_outcomes` | 0 | new |

Click `technicians` and check the header shows **RLS enabled**. Then open
**Authentication -> Policies** and confirm eleven policies exist across the four
new tables.

A second check, from the SQL Editor:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
```

---

## 4. Create a function

Already done for the four in this repo, but this is the command that made them:

```sh
npx supabase functions new match-technician
```

It scaffolds `supabase/functions/match-technician/index.ts` with a hello-world
handler. The folder name **is** the URL path, so the function above is served at
`https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/match-technician`.

The four functions in this project:

| Function | Called by | Does |
| --- | --- | --- |
| `match-technician` | client, after posting a job | Stage 1 + Stage 2, writes the Top 3 to `job_matches` |
| `job-response` | technician, and client on completion | accept / decline / reroute, cascade to rank 2 and 3, record outcomes |
| `aggregate-outcomes` | cron | recomputes rating, job counts and per-combo accuracy from `job_outcomes` |
| `technician-directory` | client, home screen | public technician list and profile, since RLS hides other people's rows |

---

## 5. Set the secrets

Both at once, straight from the local file:

```sh
npx supabase login
npx supabase secrets set --env-file supabase/functions/.env.local --project-ref nlchvhygejurjvuyluwe
```

`--project-ref` targets the project directly, so **`supabase link` is not
required and you are never asked for the database password.** Only `login` is
needed, and that is a browser click.

Or one at a time:

```sh
npx supabase secrets set TOMTOM_API_KEY=your_tomtom_key --project-ref nlchvhygejurjvuyluwe
```

List them (Supabase shows a digest, never the value):

```sh
npx supabase secrets list --project-ref nlchvhygejurjvuyluwe
```

There is also a no-CLI route: **Dashboard -> Project Settings -> Edge Functions
-> Secrets**, then Add new secret. Same result, useful if `login` gives trouble.

You do **not** set `SUPABASE_URL`, `SUPABASE_ANON_KEY` or
`SUPABASE_SERVICE_ROLE_KEY`. Supabase injects those into every function
automatically, and trying to set names with the `SUPABASE_` prefix is rejected.

---

## 6. Run locally (needs Docker)

> **Docker is not installed on this machine.** `supabase functions serve` runs
> the Deno runtime inside a container, so this whole section will fail with
> `docker daemon not running` until Docker Desktop is installed. You do not
> need it: skip to section 7, deploy with `--use-api`, and read the logs in the
> dashboard instead. Local serving is a convenience, not a requirement.

```sh
npx supabase functions serve --env-file supabase/functions/.env.local
```

Serves every function at `http://127.0.0.1:54321/functions/v1/<name>` with hot
reload.

Pass `--env-file` explicitly. Local serving does **not** read the secrets you
set with `supabase secrets set` — those only exist on the deployed project —
and whether the CLI auto-loads `.env.local` varies by version. Naming the file
always works.

Without it, the function logs `TOMTOM_API_KEY is not set` and skips the traffic
and weather factors instead of failing, so a missing key looks like a working
match with two factors quietly absent. Check the log line, not just the
response.

To hit a local function you still need a bearer token. The anon key works for
functions that only need a valid key; anything that reads `auth.uid()` needs a
real user token. Grab one by adding a temporary `print` of
`Supabase.instance.client.auth.currentSession?.accessToken` in the app, or use
the anon key while testing the unauthenticated paths:

```sh
curl -i --location --request POST \
  "http://127.0.0.1:54321/functions/v1/match-technician" \
  --header "Authorization: Bearer YOUR_USER_ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"job_id":"paste-a-real-job-uuid"}'
```

Watch the terminal running `functions serve`: every `console.log` in the
function prints there. That is your debugger.

To serve a single function without JWT verification while poking at it:

```sh
npx supabase functions serve match-technician --no-verify-jwt
```

Never deploy with `--no-verify-jwt`.

---

## 7. Deploy

`--use-api` bundles the function on Supabase's servers instead of in a local
Docker container. Use it, because Docker is not installed here. `--project-ref`
means you do not need to have run `supabase link` first.

One function:

```sh
npx supabase functions deploy match-technician --use-api --project-ref nlchvhygejurjvuyluwe
```

All of them:

```sh
npx supabase functions deploy --use-api --project-ref nlchvhygejurjvuyluwe
```

Without `--use-api` the CLI tries to start a container and fails with
`Cannot connect to the Docker daemon`.

Check the result under **Edge Functions** in the dashboard. Each function has a
**Logs** tab, which is where `console.log` output goes in production and the
first place to look when a match returns nothing.

Deployed URL shape:

```
https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/match-technician
```

The Flutter side never types that URL. `supabase.functions.invoke('match-technician')`
builds it from the project URL already in `AppEnv`.

---

## 8. Schedule the batch function

`aggregate-outcomes` is meant to run nightly. Enable `pg_cron` and `pg_net`
once, from the SQL Editor:

```sql
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
```

Then schedule the call. Replace the project ref and paste your **service role**
key — this statement lives in the database, not in the app, so it is an
acceptable place for it:

```sql
select cron.schedule(
  'sugo-aggregate-outcomes',
  '0 18 * * *',  -- 02:00 Manila time, since cron runs in UTC
  $$
  select net.http_post(
    url := 'https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/aggregate-outcomes',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

Inspect or remove the schedule:

```sql
select * from cron.job;
select cron.unschedule('sugo-aggregate-outcomes');
```

You can also trigger it by hand at any time, which is what you will do during
the demo:

```sh
curl -X POST "https://nlchvhygejurjvuyluwe.supabase.co/functions/v1/aggregate-outcomes" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -d '{}'
```

---

## 9. Common failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `401 Invalid JWT` | no or expired `Authorization` header | send a fresh user access token |
| `relation "technicians" does not exist` | migration not pushed | `npx supabase db push` |
| Function returns 0 matches | no technician rows, or none verified | seed technicians; check `is_verified` |
| `TOMTOM_API_KEY is not set` in logs | secret missing on the deployed project | `npx supabase secrets set ...`, then redeploy |
| Traffic/weather always null locally | `.env.local` missing | create `supabase/functions/.env.local` |
| CORS error from Flutter web | preflight not handled | every function here answers `OPTIONS` via `_shared/cors.ts` |
