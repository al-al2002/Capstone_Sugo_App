# Third-party APIs for RB-CARS

RB-CARS scores a technician against live context, so it needs three outside
services. This document is the runbook: register, get a key, prove the key works
with a real call against a Davao City coordinate, then put the key in the right
place.

Reference coordinate used throughout, Davao City centre:

| Field | Value |
| --- | --- |
| Latitude | 7.0731 |
| Longitude | 125.6128 |

---

## 0. The one thing to understand first: where a key lives

This is the part worth being able to defend, because it is a security decision,
not a convenience one.

**A Flutter app is not a secret-keeping place.** Anything compiled into the APK
can be extracted. `flutter build apk` produces a file anyone can unzip, and
`--dart-define` values end up as readable strings inside it. So the rule is:

| Key | Lives in | Why |
| --- | --- | --- |
| TomTom Traffic | Supabase secret, read by the edge function | Metered per request. A leaked key lets a stranger burn the free tier, and TomTom bills or throttles **your** account. It is never needed on the phone. |
| OpenWeatherMap | Supabase secret, read by the edge function | Same reasoning. Weather is only consumed by the scoring engine. |
| MapTiler | Flutter `--dart-define`, shipped in the app | The phone itself has to fetch map tiles. There is no way to hide this key, so MapTiler is designed for it: you restrict the key by **origin / package name** in their dashboard instead of hiding it. |
| Supabase `service_role` | Supabase secret only, auto-injected into edge functions | Bypasses every RLS policy. If this reaches a client, your whole database is public. |
| Supabase `anon` | Flutter, already in `lib/core/config/app_env.dart` | Grants only the `anon` role; every table stays behind RLS. Safe to ship by design. |

The split follows one line: **a key that must be secret goes on the server; a
key that cannot be secret gets restricted instead.** The edge function is our
server. It runs on Supabase, holds the secrets, calls TomTom and
OpenWeatherMap, and returns only the scores to the phone. The phone never sees
those two keys and never talks to those two APIs.

---

## 1. TomTom Traffic API

Used in Stage 2. Heavy congestion between a technician and the client lowers the
chance that technician accepts and shows up on time, so it lowers the acceptance
score.

### Register

1. Go to <https://developer.tomtom.com/> and click **Register**.
2. Confirm the email they send.
3. Sign in, open **Dashboard -> My Keys**. A key named "My first API Key" is
   created automatically.
4. Copy the key. The free tier is 2,500 requests per day, which is far more than
   a capstone demo needs.

### Test call

Traffic Flow Segment Data, absolute speeds, zoom 10, in kilometres per hour:

```sh
curl "https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/10/json?point=7.0731,125.6128&unit=KMPH&key=YOUR_TOMTOM_KEY"
```

A working key returns something shaped like this:

```json
{
  "flowSegmentData": {
    "frcCategory": "FRC3",
    "currentSpeed": 22,
    "freeFlowSpeed": 40,
    "currentTravelTime": 98,
    "freeFlowTravelTime": 54,
    "confidence": 0.9,
    "roadClosure": false
  }
}
```

### How RB-CARS reads it

Congestion is `1 - currentSpeed / freeFlowSpeed`. In the sample above that is
`1 - 22/40 = 0.45`, i.e. traffic is running at 55% of normal. The scoring code
turns that into a 0..1 traffic factor in
`supabase/functions/match-technician/clients/tomtom.ts`.

If the call fails or the key is missing, the client returns `available: false`
and Stage 2 **redistributes the traffic weight across the remaining factors**
rather than scoring everyone as zero. A dead API must not silently rank every
technician the same.

---

## 2. OpenWeatherMap

Used in Stage 2. Rain in Davao is the normal reason a home-service visit slips,
so bad weather lowers the acceptance score for travel-heavy paths.

### Register

1. Go to <https://openweathermap.org/api> and click **Sign up**.
2. Confirm the email.
3. Open **My API keys** from the account menu. A default key is already there.
4. **Wait.** A new key takes up to two hours to activate. A `401` in the first
   hour is normal and does not mean you did anything wrong.

### Test call

Current weather, metric units:

```sh
curl "https://api.openweathermap.org/data/2.5/weather?lat=7.0731&lon=125.6128&units=metric&appid=YOUR_OPENWEATHER_KEY"
```

Expected response, trimmed:

```json
{
  "weather": [{ "id": 500, "main": "Rain", "description": "light rain" }],
  "main": { "temp": 28.4, "humidity": 78 },
  "wind": { "speed": 3.6 },
  "rain": { "1h": 0.8 },
  "name": "Davao City"
}
```

### How RB-CARS reads it

The `weather[0].id` code maps to a severity from 0 (clear) to 1 (thunderstorm),
in `supabase/functions/match-technician/clients/openweather.ts`. Severity is
only applied to paths that require travel, so a shop pickup is barely affected
while a home service in a thunderstorm is heavily penalised.

---

## 3. MapTiler

Used by Flutter directly, for the location picker and later for technician
tracking. Rendered through `flutter_map`, which takes any XYZ raster tile URL.

### Register

1. Go to <https://www.maptiler.com/cloud/> and sign up for the free **Cloud**
   plan (100,000 tile loads per month).
2. Open **Account -> API keys** and copy the default key.
3. Click the key and set **Allowed origins / Allowed HTTP referrers**. For a
   mobile build there is no referrer, so also restrict by usage where the
   dashboard offers it. This is the mitigation that replaces secrecy.

### Test call

Fetch one real tile covering Davao City (zoom 12, x 3477, y 1967):

```sh
curl -o davao-tile.png "https://api.maptiler.com/maps/streets-v2/12/3477/1967.png?key=YOUR_MAPTILER_KEY"
```

A valid key returns a PNG of roughly 20-60 KB. An invalid key returns a small
JSON error body instead, so check the file size:

```sh
ls -l davao-tile.png
```

### Wire it into Flutter

The key is read from `AppEnv.mapTilerKey`, which is a `String.fromEnvironment`.
Pass it at run time:

```sh
flutter run --dart-define=MAPTILER_KEY=your_maptiler_key
```

`AppEnv.mapTilerTileUrl` builds the template `flutter_map` needs, and
`AppEnv.hasMapTilerKey` lets the location picker fall back to a plain
coordinate entry card when no key was supplied, so the app still runs for a
teammate who has not set one up.

To avoid retyping the defines, keep them in `.vscode/launch.json`:

```json
{
  "configurations": [
    {
      "name": "sugo_app (dev)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "toolArgs": ["--dart-define=MAPTILER_KEY=your_maptiler_key"]
    }
  ]
}
```

---

## 4. Putting the two server keys into Supabase

Full CLI setup is in `docs/edge-functions-setup.md`. The two commands:

```sh
npx supabase secrets set TOMTOM_API_KEY=your_tomtom_key
npx supabase secrets set OPENWEATHER_API_KEY=your_openweather_key
```

Confirm they landed (values are shown as hashes, never in plain text):

```sh
npx supabase secrets list
```

Inside the edge function they are read with `Deno.env.get('TOMTOM_API_KEY')`.

For local testing, `supabase functions serve` does **not** read your deployed
secrets. Create `supabase/functions/.env.local` instead:

```
TOMTOM_API_KEY=your_tomtom_key
OPENWEATHER_API_KEY=your_openweather_key
```

That file is git-ignored. Never commit it.

---

## 5. Quick verification checklist

| Check | Command | Pass looks like |
| --- | --- | --- |
| TomTom key live | the curl above | JSON with `currentSpeed` |
| OpenWeatherMap key live | the curl above | JSON with `weather[0].main` |
| MapTiler key live | the curl above | a PNG over ~20 KB |
| Secrets stored | `npx supabase secrets list` | both names listed |
| Flutter sees MapTiler | run the app, open the location picker | map tiles render instead of the fallback card |
