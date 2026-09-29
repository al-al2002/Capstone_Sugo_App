# SUGO auth setup

Login, registration and password reset are backed by Supabase Auth. The Flutter
side is already wired up; the steps below are the dashboard configuration it
expects.

## 1. Project keys

Defaults live in `lib/core/config/app_env.dart`, pointing at project
`nlchvhygejurjvuyluwe`. Override them per build without editing source:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

The anon key is meant to ship in the client: it only grants the `anon` role, and
every table stays protected by Row Level Security. Never ship the `service_role`
key in the app.

## 2. Database

Run `supabase/migrations/20260904000001_create_profiles.sql` against the project
(SQL Editor, or `supabase db push` with the CLI). It creates `public.profiles`,
locks it down with RLS, and adds a trigger that copies `full_name` / `phone`
from sign-up metadata into a row for each new account.

## 3. Email confirmation

**Authentication -> Providers -> Email** controls "Confirm email".

- **On** (default): sign-up returns no session. The app shows "check your
  email" and returns to login. Good for production.
- **Off**: sign-up returns a session immediately and the app goes straight to
  home. Convenient while developing and demoing.

Both paths are handled in `RegisterScreen._submit`.

## 4. Redirect URLs

**Authentication -> URL Configuration -> Redirect URLs** must include:

```
io.supabase.sugo://login-callback/
```

This is `AppEnv.authRedirectUrl`, and it is already registered on both
platforms:

- Android: an intent-filter in `android/app/src/main/AndroidManifest.xml`
- iOS: `CFBundleURLTypes` in `ios/Runner/Info.plist`

If you change the scheme, change it in all three places.

## 5. Google and Facebook

The two social buttons call `signInWithOAuth`, which opens the provider in a
browser and returns through the redirect URL above. They will fail with "That
sign-in method is not enabled yet" until you:

1. Create OAuth credentials with the provider (Google Cloud Console / Meta for
   Developers).
2. Enable the provider under **Authentication -> Providers** and paste the
   client ID and secret.
3. Add Supabase's callback, `https://<project-ref>.supabase.co/auth/v1/callback`,
   to the provider's list of authorised redirect URIs.

## 6. Password reset

`ForgotPasswordScreen` calls `resetPasswordForEmail`, which emails a link back
to the app via the same redirect URL. Handling that link to collect a new
password in-app is the remaining piece; the deep link already reaches the app,
so it is a matter of listening for `AuthChangeEvent.passwordRecovery` and
showing an "update password" screen.

## Testing without a backend

`AuthRepository` is an interface, so the screens can be driven by
`test/support/fake_auth_repository.dart` with no network at all - see
`test/features/auth/`. Run everything with `flutter test`.

## Screen structure

Login and registration are one screen, `AuthScreen`. Since the 2026-09-28
redesign there is no tab switcher: one form shows at a time, and the line
under it ("Don't have an account? Register" / "Already have an account? Log
in") swaps to the other.

```
AuthScreen                       features/auth/presentation/screens/
  AuthHeader                     widgets/auth_header.dart   (the SUGO lockup)
  LoginForm | RegisterForm       widgets/login_form.dart, register_form.dart
  AuthFooterPrompt               widgets/auth_footer_prompt.dart
```

The header is `assets/images/brand_header.jpg`, the full lockup on navy, cut
from the app icon by `tool/prepare_brand_images.py`. It is square and drawn
as tall as it is wide (clamped), so its space is reserved before the image
decodes and the form does not jump on first paint. If it cannot load, the
header draws the lockup in code (`SugoLogoMark` and the wordmark) so the
screen stays usable.

The per-tab banners that used to sit here (`login.png`, `Register.png`) went
with the tab switcher. The originals are kept in `assets/source/`, which is
not bundled.

Both controllers (`LoginController`, `RegisterController`) are provided above
the form, so a half-typed form survives the swap, and the prompt is disabled
while a request is in flight.

`/login` and `/register` both resolve to `AuthScreen`, the latter with
`initialTab: AuthTab.register`, so existing links and deep links still work.

### Forms

Neither form has a bottom "switch to the other one" prompt; the tab switcher
is the only way across.

- **Login**: email, password, "Forgot Password?" and the primary CTA.
- **Register**: full name, email, phone, password, confirm password, then the
  accent CTA.

Phone numbers accept `09XXXXXXXXX` (11 digits) or `+639XXXXXXXXX`; the field
only admits digits and a leading `+`, capped at 13 characters.
`Validators.normalizePhone` converts either form to E.164 before it reaches
Supabase.

Styling comes only from the shared tokens - `AppColors`, `AppSizes`,
`AppTextStyles` and the `InputDecorationTheme` / `ElevatedButtonTheme` in
`AppTheme.light`. "Create account" uses the default blue `PrimaryButton`,
the same as "Login", so both forms read as one flow; the orange
`PrimaryButton.accent` variant is kept for secondary actions.

Validation runs through `Form` + `Validators`, so an empty field shows its
message beneath itself in `AppColors.error`, and nothing reaches Supabase until
the form is valid.

### Switch animation

Changing tabs runs four things at once:

| Piece | What it does |
| --- | --- |
| Tab pill | A single primary pill slides between the halves over 320ms (`AnimatedAlign`); the labels cross-fade their colour |
| Banner | The two images cross-fade with a 1.04 -> 1.0 scale settle, and the 7px height difference is eased |
| Form swap | The outgoing form fades and slides a short distance out - register right, login left, matching tab order |
| Fields | The incoming form's rows cascade in via `StaggeredEntrance`, 55ms apart, each fading and rising |

The cascade is the main motion, so the outer slide is kept small (0.06) to
avoid two competing pushes. `AnimatedSize` eases the card between the two form
heights underneath.

Two things that are easy to get wrong here:

- A custom `layoutBuilder` sizes the transition box to the *incoming* child
  rather than the taller of the two. Without it the card snaps to the register
  form's height the instant the tab is tapped, and only the contents animate.
- The pill uses `easeOutCubic`, not `easeOutBack`. An overshoot curve lerps the
  alignment past `centerRight`, and the enclosing `Stack` clips the pill
  mid-flight so it looks like it is squeezing off the edge.

`StaggeredEntrance` (`core/widgets/staggered_entrance.dart`) animates paint
only - every row holds its final layout position from the first frame, so the
column never reflows mid-flight - and it honours the platform "reduce motion"
setting by jumping straight to the finished state.

`test/features/auth/auth_screen_golden_test.dart` renders both tabs to
`test/goldens/`. Goldens are platform-specific - if they fail on another
machine, regenerate with `flutter test --update-goldens`.

## Unused widgets

No screen references these any more; they are kept in case the designs return.

- `widgets/terms_agreement.dart` - the Terms of Service checkbox, dropped when
  the sign-up form was reduced.
- `widgets/auth_card.dart` - the white sheet that held a form before the
  2026-09-28 layout built its own.

Deleted on 2026-09-29: `auth_hero.dart` and `hero_figures.dart` (the painted
courier scene, superseded twice over - by the banners, then by the brand
header) and `service_chips.dart` (the header's old fallback). The "or continue
with" block went earlier, with Google and Facebook sign-in.
