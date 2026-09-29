# Phone OTP with Twilio Test Credentials

The client registration phone step, wired to Supabase Auth's phone provider.
No real SMS, no cost, and no fake UI — the real `verifyOTP` code path runs.

---

## Read this first: what Twilio test credentials actually do

This is the part that decides how the demo is run, and it is easy to get wrong.

**Twilio test credentials never deliver a message.** They validate the API
request, return a realistic response, and discard it. Nothing arrives on any
handset — not on your phone, and *not on Twilio's magic test numbers either*.

The magic numbers are **request fixtures, not inboxes**:

| Number | What it does |
|---|---|
| `+15005550006` | Valid — the API call succeeds |
| `+15005550001` | Rejected as an invalid number (error 21211) |
| `+15005550009` | Rejected as not SMS-capable (error 21614) |

They make Twilio's *API* answer in a fixed way. They do not produce a text.
The current list is in Twilio's docs under **test credentials / magic numbers**
— worth checking there rather than trusting a copy, since Twilio adds cases.

**So test credentials alone cannot complete this flow.** Supabase would
generate an OTP, hand it to Twilio, Twilio would drop it, and there would be no
code for anyone to type.

### The combination that does work

Twilio test credentials satisfy the provider configuration, and **Supabase test
phone numbers** give you a usable code:

- Supabase lets you register `number → fixed OTP` pairs on the Phone provider.
- For those numbers Supabase **skips the SMS provider entirely** and always
  accepts the fixed code.
- Everything else is the real flow: real `updateUser`, real `verifyOTP`, real
  `auth.users.phone_confirmed_at`.

That is what makes the demo completable at zero cost. Swapping to live Twilio
credentials later is a dashboard change with **no code change**.

---

## 1. Twilio: get the TEST credentials

1. Sign in at <https://console.twilio.com>.
2. On the console home, open **Account Info**, or go to
   **Account → API keys & tokens**.
3. Find the **Test credentials** section — it is separate from the live ones.
   You want:
   - **Test Account SID** (starts with `AC…`)
   - **Test Auth Token**
4. Copy both. Do **not** use the live Account SID / Auth Token: those bill you
   and send real messages.

No phone number purchase is needed for test credentials. If a `From` number is
required anywhere, `+15005550006` is the magic valid sender.

> Twilio moves things around in its console. If the labels differ, search their
> docs for "test credentials" — the distinction you are looking for is always
> **test vs live**, not which page it lives on.

---

## 2. Supabase: enable the Phone provider

In the Supabase dashboard for project `nlchvhygejurjvuyluwe`:

1. **Authentication → Sign In / Providers** (older UI: **Authentication →
   Providers**).
2. Open **Phone**.
3. Turn **Enable phone provider** on.
4. Choose **Twilio** as the SMS provider and fill in:
   - **Twilio Account SID** → your **Test** Account SID
   - **Twilio Auth Token** → your **Test** Auth Token
   - **Twilio Message Service SID / From number** → `+15005550006`
5. Leave **Enable phone confirmations** on.
6. Save.

### Then add test phone numbers — this is the important step

On the same Phone provider page there is a section for **test / demo phone
numbers** (Supabase has labelled it "Test OTP" and "Test phone numbers" in
different releases). Add pairs, one per line:

```
+639171234567=123456
+639060000000=654321
```

Those numbers now verify with that exact code and never touch Twilio.

**Use your real number here for the defence.** You type your own number, you
type `123456`, the flow completes, and nothing is sent or billed.

---

## 3. How the demo actually looks

1. Client reaches **step 3, Confirm your number**.
2. Types the number you registered as a Supabase test number.
3. Taps **Send code** → `auth.updateUser(phone:)` runs for real.
4. Types the fixed OTP → `auth.verifyOTP(type: phoneChange)` runs for real.
5. Supabase sets `auth.users.phone_confirmed_at`.
6. The app calls `confirm_phone_verified()`, which **re-reads that column
   server-side** before setting `client_verification_status.phone_verified`.
7. The step goes green and registration continues.

If you enter a number that is *not* registered as a test number, Supabase will
try Twilio, Twilio will accept and discard it, and no code will ever arrive.
That is expected behaviour for test credentials, not a bug.

---

## 4. Going to production

Only two things change, both in the dashboard:

1. Replace the Test Account SID / Auth Token with the **live** ones.
2. Buy a Twilio number (or a Messaging Service) and set it as the sender.
3. Remove the test phone numbers so nobody can verify with a fixed code.

No Flutter change. No redeploy. **No Twilio credential exists anywhere in this
repository or in the app binary** — which is the point: a credential shipped in
a client app is a credential anyone can extract.

For a Philippine deployment, Semaphore is usually cheaper than Twilio and needs
no per-country setup. The custom edge function `send-phone-code` still supports
it if you ever prefer that route over Supabase Auth.

---

## 5. Why the app cannot just set `phone_verified`

`client_verification_status` has no insert or update policy for
`authenticated`. Every column on it is either awarded (`trust_level`), earned
(`avg_rating_from_technicians`) or held against the client (`no_show_count`),
so a self-writable `phone_verified` would let anyone skip the step by writing
`true`.

Instead the app reports that it verified, and `confirm_phone_verified()`
**checks that claim against `auth.users.phone_confirmed_at`** — a column only
GoTrue writes, and only after matching a real OTP. The client's word is never
the evidence.

Verified against the live database:

| Check | Result |
|---|---|
| `confirm_phone_verified()` with no confirmed phone | **Refused** — "This phone number has not been verified yet" |
| After GoTrue sets `phone_confirmed_at` | `phone_verified = true` |
| `profiles.phone` mirrored | `+639171234567` (E.164 restored) |

---

## 6. Why `updateUser`, not `signInWithOtp`

The person is already signed in with email and password when they reach this
step. `signInWithOtp(phone:)` starts a **new phone-identity session** and would
replace the account they registered under — leaving a half-finished
registration orphaned behind them.

`updateUser(UserAttributes(phone:))` attaches a number to the *current*
account and sends an OTP for it; `verifyOTP(type: OtpType.phoneChange)`
confirms it. That is the pairing meant for "verify a number for whoever is
signed in", and it is what
`lib/features/onboarding/services/phone_verification_service.dart` uses.

---

## 7. Known limitations

1. **Test numbers are a fixed-code bypass.** Anyone who knows the number and
   the code can verify it. Remove them before production.
2. **Twilio test credentials prove the integration, not delivery.** They
   confirm the request is well-formed and authorised. They tell you nothing
   about whether a real message would arrive, so budget a live test before
   launch.
3. **Rate limits still apply.** Supabase throttles OTP requests per project;
   the screen surfaces that as "Too many attempts. Wait a moment."
4. **The legacy custom OTP is still in the schema.** `phone_verifications`,
   `send-phone-code` and `verify-phone-code` remain and still work; they are no
   longer used by client registration. `initialize_client_trust_profile()`
   accepts either source, so an account verified under the old flow is not
   asked again.
