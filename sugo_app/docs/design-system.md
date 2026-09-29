# The SUGO design system: "Dispatch"

What the UI is built from, and the reasoning behind each decision. Read this
before changing anything visual. Most of the questions that come up while
building a screen are already answered here.

This file describes the system after the **Dispatch redesign and rebrand of
2026-09-29**. For the earlier 2026-09 redesign, which chose the palette and the
typeface, see [`redesign-2026-09.md`](redesign-2026-09.md).

---

## 1. The idea

*Sugo* means sending someone on an errand, and that is what the app does. It
sends a technician to a broken device and back: "from your home to our shop",
as the splash poster says.

So a job is drawn as a trip, everywhere a job's progress is shown. The trip is
`SugoRouteLine`: a dashed road, named stops, the ground already covered solid
in SUGO blue, and the logo's service van where the job is now (see section 8).
That is the one strong element. Everything around it is kept quiet: flat white
surfaces, a hairline edge, one navy action per screen.

The direction was picked from three options in Phase 0. The other two were
"Workbench", with repair-ticket cards, and "Blue sky", with gradient headers
everywhere. It was picked because:

* It comes from the name.
* It is honest by construction (section 8).
* It fixes the audit's inconsistencies.
* It keeps the brand's colours and typeface, so what changed is structure, not
  identity.

It matches ui-ux-pro-max's profile for home-service apps: flat design that is
accessible, a trust blue and a safety orange.

## 2. The brand

The paper-plane logo was retired on 2026-09-29, because the client found it
read as Telegram's. The new artwork has two sources:

* `assets/source/icon 2.png`: a house with a wrench, a swoosh and a service van.
* `assets/source/splash 2.png`: the poster.

Both sit in `assets/source/`, which pubspec does not declare, so the
full-size originals (about 8 MB with the retired artwork) never reach the APK.

`tool/prepare_brand_images.py` cuts every file the apps use from those two:

| Output | Used by |
|---|---|
| `assets/icon/app_icon_{rounded,full,adaptive}.png` | `dart run flutter_launcher_icons`, which covers Android (adaptive included), iOS, web, Windows and macOS |
| `brand_emblem.png` | `SugoLogoMark`, the matching screen's disc, and the admin panel (`public/images/brand-emblem.png`, plus its favicon) |
| `brand_header.jpg` | the login and register header |
| `splash_art.jpg` | the splash: the poster with its *drawn* "Get Started" button painted out |
| `banner_technician.jpg` | the home screen's "Need a tech fix?" banner |

The wordmark (`SugoLogo`) keeps the orange stroke on the "O", painted to match
the artwork.

## 3. Colour: one colour, one job

The brand values are unchanged from the matching brief. The Dispatch redesign
moved only the ground and the hairline, and added one ink.

| Token | Value | Job |
|---|---|---|
| `primary` | `#062B5C` navy | the brand, and the one primary action per screen |
| `secondary` | `#087FEA` SUGO blue | *pointing*: focus, selection, the distance already covered on a route |
| `secondaryDark` | `#0663C4` | SUGO blue as **text**: links, text buttons |
| `cyan` | `#11C5E8` | *recommending*: the "Recommended" mark, match bars, the splash's "Get started" |
| `accent` | `#F59E0B` orange | *marking*: urgency, unread badges, stars |
| `accentDark` | `#B45309` | orange as **text**, and any orange that white words sit on |
| `onAccent` | `#10233F` | words on an orange fill: count badges, the accent button (7.3:1) |
| `background` | `#F5F7FA` Paper | the page ground |
| `border` | `#E3E8EF` Hairline | the edge of every card, field and tile |
| `textPrimary` / `textSecondary` | `#10233F` / `#5F6E84` | body ink, and muted ink (5.2:1) |
| `hint` | `#8C95A8` | placeholders and disabled labels **only**: it is 3:1 |

**Bright for marks, dark for words.** Five of the brief's values fail WCAG AA
as text on white. The worst is orange at 2.1:1. Wherever a colour is printed as
text, or has white text on it, the darker token of the same hue is used. The
roll-out found this rule broken in several places:

* the technician's vacation panel, which had white words on bright orange
* the "Acceptance" score
* the tracking stages "In repair" and "Ready for collection"
* the count badges
* the "Needed today" and "Elite" pills
* the rating bars

All of them now use `accentDark` or `onAccent`.

**Never colour alone.** `SugoStatusBadge` requires an icon *and* a label.
`SugoTimeline` and `SugoRouteLine` tell done, current and ahead apart by
*shape*: filled, marked, hollow or dashed. Both survive greyscale.

## 4. Surfaces, corners and depth

**Flat, with an edge.** A resting card is white on Paper with a 1px Hairline
edge, and no shadow. `SugoCard` draws the edge itself. A shadow under *every*
card was the template look: when everything floats, nothing does, and each
blur costs a paint on a cheap phone.

**Shadows mean "this floats".** They are kept only for:

* `AppElevation.xl`: sheets, dialogs, and sticky footers over a list
* `AppElevation.navBar`: the bottom bar
* `AppElevation.lg`: a card over a map, and the splash button over the poster

`AppElevation.glow` is no longer used anywhere. A lit button on a flat page is
the one thing on screen pretending to float, and the fill alone already marks
it.

**Selection** is a 2px SUGO-blue edge on a pale tint, as on the device grid
and the service-path cards. It is not a lifted shadow.

**Two corners.** There used to be five tokens and a dozen hand-typed values.
The pairs below match the Dispatch spec (a 12dp radius and a 20dp sheet
radius), and they are what `AppSizes` should hold:

* `AppSizes.radius` = **12** for everything on the page: cards, buttons,
  fields, tiles.
* `AppSizes.sheetRadius` = **20** for things anchored to an edge or floating:
  bottom sheets, dialogs, the auth sheet. Chat bubbles use it too.

A corner size signals what kind of object something is. The old names
(`panelRadius`, `tileRadius`, `fieldRadius`, `buttonRadius`, `cardRadius`) are
aliases, so existing screens picked up the change at once.

## 5. Type

Plus Jakarta Sans, bundled in `assets/fonts` as five static weights under the
SIL Open Font License. It has a tall x-height, open numerals, and character in
the heavy weights.

Six sizes, and nothing in between:

| Size | Styles | For |
|---|---|---|
| 28 | `display`, `displayLarge` | a screen's opening line, one per screen at most |
| 20 | `title`, `headline`, `stat`, `price` | screen titles, a headline figure |
| 16 | `sectionTitle` | section and card headings |
| 15 | `body`, `bodyStrong`, `subtitle`, `titleSmall`, `button`, `field` | running text, a row's title, a button |
| 13 | `caption`, `label`, `link` | supporting text, field labels, links |
| 12 | `micro`, `overline`, `statLabel` | metadata: a time, a distance |

Nothing is smaller than 12. The only sizes outside the scale are graphics, not
text: the logo (34, 44) and the faint initials behind a technician's hero (72).

**Sentence case everywhere.** That covers labels, eyebrows ("Your booking",
not "YOUR ACTIVE BOOKING"), fields ("Email address") and buttons ("Book now").
Only names keep their capitals: "Terms of Service", "RB-CARS".

**Tracking tightens as size grows; line-height loosens as size shrinks.** A
28px headline at body tracking reads as loose; body copy needs 1.5 to find the
next line.

### The font-family trap

The theme sets the family, and `Text` merges with the inherited style. Three
things do **not** merge: they *replace* the inherited style. So they must name
`AppTextStyles.fontFamily` themselves, or the phone's own font appears:

* `ButtonStyle.textStyle`: this is how the "Book now" label, both buttons on
  the technician's availability card, and "Edit post" fell back.
* `DefaultTextStyle` and `AnimatedDefaultTextStyle`: this is how the matching
  screen's checklist fell back.
* A `TextPainter` in a `CustomPainter`, which inherits nothing at all.

## 6. Motion

The durations are `fast` 140ms, `base` 240ms, `slow` 360ms and `page` 420ms.
Almost everything decelerates. `playful`, the one curve that overshoots, is
kept for once-per-flow moments.

**"Remove animations" is honoured** through `AppMotion.reduced(context)`. The
audit found it in 6 places. Now every looping or decorative animation holds
still under it:

* the skeleton shimmer and the status pulse
* the delete bin
* the matching emblem, where the clock keeps running for the checklist and
  progress, and only the orbit stops
* the score bars
* the timeline's current node
* the bottom-nav pill
* the route van
* the splash loader and the splash poster

Motion that *answers* a tap stays: a button dip, a sheet opening.

## 7. Touch

The floor is **48dp**, Material's and Android's. It used to be 44, the iPhone
figure, and SUGO is used mostly on Android.

* A small `SugoButton` draws 40 tall and answers taps across a 48dp band.
* Text buttons use `tapTargetSize.padded`.
* Icon buttons, the chat send button and the posting flow's back button are 48.

## 8. The route line

`SugoRouteLine` in `core/widgets` has these parts:

* **Stops:** named stops, `BookingRoute.stops`, which are Posted, Matched,
  Booked and Fixed.
* **Marker:** the van from the logo, on a navy disc. It becomes a tick on
  arrival.
* **Line:** solid SUGO blue behind the van, a dashed hairline ahead.
* **Stops drawn:** filled discs behind, hollow rings ahead.

**It is honest by construction.** A `SugoRoutePosition` is either *at* a stop
or *leaving* one, meaning half-way along the next leg. There is no free
percentage, because the database records stages, not "62% of the way".

Every position comes from data:

* `BookingRoute.forStatus(jobs.status, offerPending:)`, or one of the named
  positions.
* A live tracking row refines "Booked" to "under way".
* A cancelled job has no route at all.

The van slides only when the data changes, and never on its own.

Where it appears:

* the client home's booking card
* the matching screen's job summary
* "Request sent"
* the job detail status card
* the technician's active job, so both sides watch one trip

`SugoTimeline` is its vertical form and shares its colours.

## 9. The shared widgets

| Widget | Why it exists |
|---|---|
| `SugoCard` | The page's panel: 12 corners, hairline, a press dip |
| `SugoButton` / `SugoOutlinedButton` | One button API: a variant for *meaning*, a size for context |
| `SugoIconButton` / `SugoCountBadge` | Round actions, with a count (ink on orange) or a dot |
| `SugoStatusBadge` | A status as icon + word + tone, never colour alone |
| `SugoAppBar` | One title style (20, left), one back chevron, one background |
| `SugoRouteLine` | The job as a trip (section 8) |
| `SugoTimeline` | Done / current / upcoming, distinguished by shape |
| `SugoListTile` / `SugoListGroup` | Profile, settings, help and addresses |
| `showSugoBottomSheet` / `SugoSheetOption` | Handle, title, close, keyboard inset, height cap |
| `showSugoConfirmDialog` | The question as the title, outcomes as the buttons |
| `SugoSearchField` | The same 48dp bar as a button (home) and live (search) |
| `SugoBottomNav` | The bar on the edge, a pill behind the active icon, the compose square |
| `SugoSkeleton` / `SugoSkeletonList` | Loading, shaped like the content |
| `SugoEmptyState` | Empty, error and loading at one size, so nothing jumps |
| `SugoAvatar` | Coloured initials, or a photo |
| `SugoLogo` / `SugoLogoMark` | The wordmark with its orange stroke; the emblem tile |
| `AppTextField` | Focus, valid and invalid states |
| `Fmt` | Dates, times and pesos, written the same way everywhere |

Only one raw `AppBar` is left, and it is on purpose: the matching screen's,
which is transparent over navy with white icons.

`PrimaryButton` stays for the screens and tests that find it as an
`ElevatedButton`. It looks identical to `SugoButton`.

**Skeletons, not spinners, for a whole screen.** A skeleton reserves the real
footprint, so nothing jumps when the data lands. Spinners remain only *inside*
a control that is busy, such as a button, a switch or an upload.

**Avatars use initials.** Most rows have no photo. The tint comes from the
name, so a person is the same colour everywhere.

## 10. Screens worth knowing

**The splash** runs in this order:

1. The poster fades in.
2. The van drives a dashed road under "Getting SUGO ready...".
3. The splash waits until Supabase has restored the session **and** 1.5s have
   passed. That minimum is the cost of a visible loading animation, and it is
   spent decoding the login header.
4. Then it depends on who is using the phone:
   * **Signed out:** a real "Get started" appears where the poster's drawn one
     was. It is cyan with navy words (7.8:1); a darker blue vanished into the
     poster.
   * **Signed in:** they go straight to their dashboard.

**The client home** has four parts:

* A light header with the emblem, the inbox and the bell.
* One hero: the booking's route card, or the "Need a tech fix?" banner.
* Services.
* Top-rated technicians.

The navy header of the 2026-09-28 reference was replaced, so that the eye lands
on the booking.

**The technician dashboard** runs in order of urgency:

1. Availability.
2. Incoming requests.
3. The active job.
4. This week's numbers.
5. Reviews.

The stats used to sit above the requests, below the fold.

**The bottom bar** sits on the screen's edge with a hairline. The client's
compose button is a navy square in the middle. The technician has none, and
four tabs spread evenly.

## 11. Two traps worth knowing

**`late final` controllers.** A `late final` initialiser on a `State` runs on
*first access*. If `build` skips it on some path, `dispose()` creates it on an
unmounted element, and the error ("Looking up a deactivated widget's
ancestor") is followed by dozens of unrelated layout assertions. Assign
controllers in `initState`.

**Form validation.** Let `TextFormField` render `errorText`. `Form.validate()`
sets it on untouched fields, which is what makes an empty form report its
errors on submit. `AppTextField` layers focus and valid states on top of that
rather than replacing it.

## 12. Things deliberately not done

* **No drag handle on the auth card.** It does not drag.
* **No bounce in the navigation bar.** It is pressed dozens of times a
  session.
* **No count on the nav badge.** A growing "17" reads as a debt; the header
  inbox shows the count instead.
* **No glow on any button.**
* **No dark mode.** One theme exists, and a switch that did nothing would be a
  support ticket.

## 13. The audit, before and after

These were counted in `lib/features` at Phase 0 and again at the end of the
roll-out.

| Measure | Before | After |
|---|---|---|
| Hand-typed font sizes | 370, in 25 sizes | 293, all on the six-size scale |
| Text smaller than 12px | 21 | 0 |
| Raw `AppBar` vs `SugoAppBar` | 17 vs 11 | 1 (on purpose) vs 27 |
| Button labels in the phone's font | 4 (+1 checklist) | 0 |
| Button glows | 8 call sites | 0 |
| Hand-typed corner radii | 12 different values | 1 left |
| Touch-target token | 44 | 48 |
| "Remove animations" honoured | 6 places | every decorative loop |
| Skeletons | 25 | 35 |

## 14. Golden tests

There are twelve goldens in `test/goldens/`. They were regenerated flow by flow
during the roll-out, each time for a stated reason.

```bash
flutter test                    # 290 tests
flutter test --update-goldens   # after an intentional visual change
```

The home header takes a `now:` so its greeting does not depend on the time the
suite runs. A golden taken in the afternoon used to fail every morning.

Goldens render in the test font, where letterforms become boxes. That is fine
for layout and colour, but useless for judging type. To *look* at a screen,
render it in a scratch test:

1. Load `assets/fonts/PlusJakartaSans-*.ttf` and the SDK's
   `materialicons-regular.otf` through a `FontLoader`.
2. Set `debugDisableShadows = false`, and restore it before the test ends.
3. Write the golden to a path outside `test/goldens`.

Regenerating a golden is a deliberate act. If one fails and you did not mean to
change that screen, the golden is right and the code is wrong.
