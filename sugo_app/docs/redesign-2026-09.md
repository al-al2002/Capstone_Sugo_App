# The 2026-09 SUGO redesign

What changed across the whole app, why each decision was made, and what you
have to run yourself. Read `design-system.md` first for the tokens and shared
widgets; this document is the *change*, screen by screen.

The rule this redesign worked under: **improve the interface, do not invent
the product.** Every screen shows something the database can actually answer
for. Where the brief asked for a feature SUGO has no data for, the app says so
plainly instead of drawing a convincing placeholder - those cases are listed
under [What was deliberately not built](#5-what-was-deliberately-not-built).

> **Superseded in parts on 2026-09-29.** A second, whole-app pass - the
> "Dispatch" redesign - and a rebrand followed this one:
>
> * It kept this redesign's palette, typeface and features.
> * It changed how surfaces, type and motion are applied.
> * It retired the paper-plane logo.
> * It added the booking route line.
>
> The direction, why it was chosen over two alternatives, and the audit's
> before-and-after numbers are in [`design-system.md`](design-system.md).
> Where the two documents disagree, that one is current. Examples: the navy
> home header in section 3 is now light, and the floating nav pill is now a
> bar on the edge.

---

## 1. The server-side changes

```bash
cd sugo_app

# Every migration listed below.
supabase db push

# Push wording for a photo message ("Sent a photo" instead of an empty line).
supabase functions deploy notify-event

# The technician's route back to the client on a pickup job.
supabase functions deploy job-route
```

| Change | What it does | Applied to `nlchvhygejurjvuyluwe` |
|---|---|---|
| `20260923000001_chat_photos` | `job_messages.image_path`, the relaxed body check, the private `chat-photos` bucket, the "📷 Photo" preview | ✅ 2026-09-23 |
| `notify-event` redeploy | "Sent a photo" instead of an empty push | ✅ 2026-09-23 |
| `20260923000002_community_photos` | `community_posts.image_path`, the public `community-photos` bucket, `image_path` on `community_feed` | ✅ 2026-09-23 |
| `20260923000003_negotiation_chat` | an offered technician counts as a job participant; the client's inbox lists a pending negotiation | ⬜ **pending your approval** |
| `job-route` redeploy | routes a technician to the client on both legs of a pickup job | ⬜ **pending** |

The last two are flagged rather than applied because the migration **widens a
read boundary** - see [§7](#7-messaging-before-acceptance) for exactly which
one and why the objection the original design raised no longer holds.

Until each `db push` runs, the app degrades honestly rather than failing
generically:

* a chat photo reports *"Photo sharing is not set up on the server yet"*;
* a community photo reports *"Photos on community questions are not set up on
  the server yet"*, and the question itself still posts;
* a technician messaging before acceptance gets the RLS refusal as *"This
  conversation is closed"*, and Accept/Decline are unaffected.

Everything else is client-side. `flutter pub get` is enough:

```bash
flutter pub get      # picks up three newly-declared (already transitive) packages
flutter run
```

### The three new dependencies, and why none of them is really new

| Package | For | Why it costs nothing |
|---|---|---|
| `shared_preferences` | favourites, recent searches, notification read state, intro-seen flag | already pulled in by `supabase_flutter` to persist the session |
| `url_launcher` | the Call button and "Open in maps" | already pulled in by `supabase_flutter` for the OAuth browser |
| `intl` (now used more) | one date/money formatter for the whole app | already a direct dependency |

Each was *already in the lock file* as a transitive dependency. Declaring them
directly only makes it legal to import them - no new download, no new native
plugin, no change to the Firebase pins in `pubspec.yaml`.

The one genuinely new asset is the typeface: five static weights of Plus Jakarta
Sans (~640 KB) in `assets/fonts`, SIL Open Font License, licence file included.

---

## 2. The brand

| | Before | After |
|---|---|---|
| Primary | `#1877F2` (Facebook blue) | `#0F2A5C` deep navy |
| Secondary | — | `#2563EB` modern blue |
| Accent | `#FF7A00` | `#F2811D`, plus `#B4530A` for text |
| Type | platform default (Roboto) | Plus Jakarta Sans, bundled |

**One colour, one job.** Navy is the brand and the primary action. Blue
*points*: links, focus rings, selection, progress, the route line on a map.
Orange *marks*: unread badges, rating stars, the live pulse. When one colour did
all three - which is what the old single blue did - none of them meant anything.

**State colours are the 700 shades.** Green `#15803D`, amber `#B45309`. The
brighter 500s that most kits use sit near 3:1 on white, and this app prints
them as *text* ("Confirmed", "Waiting 3h"), so they had to clear 4.5:1.

---

## 3. What changed, screen by screen

### The shell

* **Splash** - navy gradient, mark and wordmark animating in, on screen only as
  long as the session takes to restore. No artificial delay.
* **Intro carousel** (new) - four slides, shown once per install, skippable from
  the first. The illustrations are built from real UI fragments rather than
  stock art, so they are sharp at any density and cost no download.
* **Offline banner** (new) - a slim strip that appears when the server cannot
  be reached. It probes Supabase itself rather than the Wi-Fi radio, because a
  phone on a café hotspot behind a sign-in page reports "connected" and can
  still load nothing.
* **Bottom navigation** - Home · Bookings · **+** · Community · Profile.
  Messages and notifications are both header icons. Community held its tab
  (it briefly lost it to Messages; you reversed that on 2026-09-23, and the
  reasoning is in [§8](#8-the-nav-swap-back)).

### Home

Rebuilt around what someone opens the app to do:

1. Header: brand, notification bell with count, avatar.
2. Greeting, then **search** (reinstated at your request - it opens a dedicated
   screen so the dashboard never has results pushing it around).
3. **The active booking**, as a navy hero with live status, ETA and the two
   actions that matter. The brief's rule was that nobody should have to
   navigate to find it.
4. Eight service categories, then "Recommended for you" (drawn from what this
   client has actually had repaired), top-rated technicians, recent bookings,
   and the community card.

A brand-new account sees a three-step "How SUGO works" card instead of a column
of empty states.

### Discovery, booking and tracking

* **Find a technician** (new screen) - the full verified directory with search,
  a filter sheet (service, distance, rating, price band, availability,
  favourites) and five sort orders. It uses the `list` action of the existing
  `technician-directory` function, which had been written but never called.
* **Booking flow** - unchanged in structure (it is the RB-CARS flow, and the
  matching engine decides the order), restyled throughout. A category tile or
  a search result now drops you straight onto the problem step with the device
  already chosen, with the device step still behind you.
* **Request sent** (new screen) - the confirmation after picking a technician:
  reference, summary, and a timeline of what happens next.
* **Live tracking** - the map is now the screen, with a draggable sheet over it
  carrying ETA, straight-line distance, freshness, the technician and the
  stage timeline. The marker eases between fixes instead of teleporting.

### Bookings, chat, notifications

* **Bookings** - counts on the tabs, skeletons, status badges with icons, and
  the price on the card.
* **Booking detail** - a status hero with the right action, a single timeline
  that folds the delivery stages into the booking's own lifecycle, zoomable
  photos, and a price card that states who actually gets paid.
* **Chat** - photos (camera or gallery), preview-and-remove before sending,
  upload progress in the bubble, retry on failure, a full-screen zoomable
  viewer, and an unread divider.
* **Notification centre** (new) - derived from jobs, tracking and unread
  messages. See below for what that means.

### Profile

Profile now reaches everything the brief asks it to: favourites, saved
addresses, community, notifications, help, settings, sign out.

* **Saved addresses** (new) - full CRUD with labels, landmarks and a default.
  The table always supported many addresses; nothing but registration ever
  wrote one.
* **Settings** (new) - account, alerts, privacy, location, support, about.
* **Help & support** (new) - searchable FAQ written from what the database
  actually enforces, plus three ways to reach a person.

---

## 4. The notification centre is derived

SUGO stores no notifications. Push is sent by `notify-event` and forgotten, and
you chose (2026-09-22) not to add a table for it. So the centre is *computed*
on each load from data that already exists:

| Source | Becomes |
|---|---|
| `jobs.status` + the requested technician | Booking and Service items |
| `job_tracking.stage`, delay fields | Tracking items |
| `job_conversations.unread_count` | Message items |

Two consequences worth being able to state at a defence:

* **Read state for chat is the server's** (`job_messages.read_at`); for
  everything else it is this device's, kept in `shared_preferences`.
* **Times are real where the database records one** - a job's `created_at`, a
  match's creation, a tracking row's `started_at`, a message's `created_at`.
  A status change like "confirmed" has no timestamp of its own, so it is
  stamped the first time the device sees it. On a first run every existing item
  is backdated to its job's `created_at` and marked read, so installing this
  version does not present a year of history as unread alerts.

---

## 5. What was deliberately not built

Each of these is in the brief. Each would have needed either data SUGO does not
have or a promise it cannot keep.

| Asked for | What was done instead, and why |
|---|---|
| Payment, receipts, service fee, total | SUGO takes no payment - clients pay technicians directly and there is no payments table. The booking shows the *budget* as a budget, states the arrangement plainly, and offers a "booking summary" rather than a receipt. |
| "Remember me" on login | Supabase persists the session either way. A switch that changed nothing would be decoration. |
| Social sign-in | The OAuth methods still exist on the controller but no provider is configured. Buttons for them would fail. |
| Dark mode / appearance settings | One theme exists. A dark-mode switch that did nothing is a support ticket. |
| Per-type push switches | `notify-event` decides what to send from the job's own data and reads no per-category preference. The one switch that *does* something - removing this device's token - is what the settings screen offers, next to per-category filters for the in-app centre. |
| Typing indicators, online status | No presence data. Nothing to read. |
| Favourites that sync | Stored on the device by your decision, rather than adding a table. The UI says "on this phone". |
| 5 job photos | The picker caps at 4, which is the existing tuned grid and within the brief's recommended maximum. |

---

## 6. Testing

```bash
flutter analyze                 # clean
flutter test                    # 254 tests
flutter test --update-goldens   # after an intentional visual change
```

Goldens were regenerated on purpose - the palette, typeface and several card
layouts changed by design. Three tests changed with them, each for a stated
reason:

* `auth_screen_test` asserted the header's *asset name*; the header is drawn in
  code now, so it asserts the headline copy instead.
* `post_to_loader_test` pumps past the page transition before checking the old
  screen is gone: the app now uses the Android 14 fade-through, which keeps the
  outgoing route mounted about twice as long as the old zoom.
* `bookings_card_golden_test` captures a fixed frame instead of
  `pumpAndSettle`, because a live booking's status dot now pulses and an
  animation that repeats for ever never settles.

Two real defects were found by rendering screens with the production font and
fixed: a 1px overflow in the match-score ring at 1.3x text scale, and the auth
tab labels silently falling back to the platform font (`AnimatedDefaultTextStyle`
replaces the inherited style rather than merging with it).

---

## 7. Messaging before acceptance

A client's budget is a guess made by somebody who does not know what the repair
costs. When ₱800–1,500 will not cover the part, the technician used to have two
options: decline without a word, or accept work they would lose money on.

`20260923000003_negotiation_chat` adds a third. `is_job_participant()` now also
returns true for the technician a client has **offered** the job to, so the two
of them can talk before the answer.

### Why the original objection no longer applies

`20260907000013_job_messages.sql` argued the opposite, and was right at the
time:

> Three technicians receive every offer, and opening a channel to all three
> would let two strangers message a client about a job they will never do -
> and would leak that the client is shopping around.

Every clause of that was about the old meaning of `offered`.
`20260916000002_offer_requires_client_selection` split it in two:
`shortlisted` is "the engine ranked you", `offered` is "the client picked you".
There is now exactly one `offered` technician per job, and the client put them
there deliberately. The shortlist never leaves `shortlisted`, which this
migration does not touch.

### What is deliberately *not* widened

**`jobs` RLS is untouched.** `jobs_technician_select_assigned` still hides an
unassigned job, so the technician can talk to the person without being handed
their name, their address or their pin. The thread title on their side reads
"Client", because that is genuinely all they know.

That is also why a pending negotiation appears in the **client's** inbox and
not the technician's: `job_conversations` reads `jobs` under the caller's own
RLS, and making a row appear for them would mean releasing the client's row.
The technician reaches the thread from the offer card instead - which is where
they are already deciding - and `ChatService.unreadForJob` puts the dot on it.

**Access ends when the offer does.** Decline, or be passed over, and the match
turns `declined`; the predicate stops matching and they keep nothing. The
client keeps the thread, because it is their job and their record of what was
agreed.

---

## 8. The nav swap back

Messages took Community's tab in the first pass. You reversed it on
2026-09-23: **Home · Bookings · + · Community · Profile**, with Messages as a
header icon beside the bell.

The reasoning is the same one that put notifications in the header. A chat is
something you *return to*, one tap from wherever you are, and its badge is the
whole of what you need at a glance. Community is a place you *go*, and a
destination earns a tab. Giving the shallower thing the deeper slot had it
backwards.

---

## 9. The technician's side, filled in

Four gaps, all on the technician half of the app, all closed on 2026-09-23.

### A notification centre

`job-response` has pushed "New job request" since 20260922000006 - but a push
swiped off a lock screen was gone, and the only way to find out what had come
in was to scroll the dashboard. There is now a bell in the technician header,
reading the same derived feed the client's does
([§4](#4-the-notification-centre-is-derived)) from their own sources:

| Source | Becomes |
|---|---|
| `job_matches` where `status = 'offered'` | "New job request" |
| `job_return_preferences` on live jobs | "They will collect it" / "They want it delivered" |
| `job_conversations` unread counts | Message items |

A request item pops back to the dashboard rather than opening a booking screen:
the job row is not theirs to read until they accept it, so the offer card is
the only place it exists.

### "View task"

The offer card carried urgency, device, distance and budget. Everything else
the client wrote - the make, the exact model, the symptom in their own words,
their photos, the full budget range - was in `score_breakdown.job` and not on
screen. **`brand` and `device_detail` were not even parsed**: the matcher has
sent both since 20260907000010 and `JobSnapshot.fromJson` dropped them on the
floor, so a technician could not see whether it was an Acer or a MacBook.

One line of Dart fixed the parse; a sheet shows the rest. Still no name and no
address - those unlock on acceptance.

### The client decides how the unit comes back

The fork after a workshop repair - deliver it, or hold it for collection - was
the **technician's** to pick, on a screen with two buttons. It is the client's
call: only they know whether they can get across town on a Tuesday.

* The client is asked at one stage, `in_repair`, and only there. Before it
  there is nothing to bring back; after it the unit has been moved and
  `set_return_method()` refuses a switch to delivery anyway.
* The technician's two buttons are gone. They get one, and it follows the
  client: *"Start the delivery"* or *"Mark it ready for collection"*. A card
  above it says which they asked for, or that nobody has chosen yet and
  delivery is the default.

### A route home on a pickup job

`job-route` refused anything that was not a home visit - so the one person who
actually had to drive to an address on a pickup job was the one the app would
not navigate. It now routes the technician to the client on **both** legs,
going to collect and coming back, and refuses in between with a reason ("the
client is collecting this one from your shop") rather than a generic 409.

---

## 10. The community composer

Two changes, both about the moment somebody is trying to describe a fault they
do not have the words for.

**A back button.** The composer covered the feed and the only ways out were a
drag on the grabber, which is not obvious, and a Cancel button below the fold
once the keyboard was up. There is now an arrow at the top left, where everyone
looks - and because a half-written question is worth more than a tidy
dismissal, it confirms before discarding a draft. The system back gesture goes
through the same guard, so there is no route out that skips it.

**An optional photo.** One picture, camera or gallery, previewed with a way to
remove or replace it before posting. Optional and capped at one: a feed of
galleries scrolls badly, and the second photo of the same fault adds far less
than the first.

`community-photos` is **public-read**, unlike the private `chat-photos`
bucket - a community question is published to a feed every signed-in user can
already read, so the photo is published too, and a public URL renders from the
CDN without minting a signed URL per image per viewer. Uploads are still
confined to the author's own folder by the storage policy.

It is uploaded *before* the row is inserted, so a failed upload costs nothing:
the user sees "could not upload" with their draft still in front of them,
rather than a posted question they now have to edit or delete.

On the feed the photo is a fixed 66px square beside the text, so a question
with a picture is the same height as one without and the feed scrolls in one
rhythm. On the question itself it is full width and opens the same zoomable
viewer the job photos use - "is that a capacitor or a burn mark" is a question
that needs pinch-zoom.
