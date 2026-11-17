<!DOCTYPE html>
<html lang="en" class="h-full">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Sign in · SUGO Admin</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        // The SUGO palette, taken from lib/core/constants/
                        // app_colors.dart so the console and the app read as
                        // one product (brought in line on 2026-09-29; it was
                        // still the retired #1877F2 blue and #FF7A00 orange).
                        //
                        // One rule carried over from the app: bright for
                        // marks, dark for words. `brand`, `accent` and `warn`
                        // are the *text* shades, because this console prints
                        // them as words and puts white words on them.
                        brand: {
                            DEFAULT: '#0663C4', // SUGO blue, text shade: 5.8:1
                            dark: '#054FA0',
                            light: '#087FEA', // SUGO blue, for fills only
                            soft: '#EAF5FF',
                            softer: '#F4F9FF',
                        },
                        navy: '#062B5C',
                        accent: {
                            DEFAULT: '#B45309', // orange as text: 5.0:1
                            light: '#F59E0B', // SUGO orange, for fills only
                            soft: '#FEF3DE'
                        },
                        ink: {
                            DEFAULT: '#10233F',
                            muted: '#5F6E84'
                        },
                        line: '#E3E8EF', // Hairline
                        canvas: '#F5F7FA', // Paper
                        ok: {
                            DEFAULT: '#157F4B',
                            soft: '#EAF7F0'
                        },
                        warn: {
                            DEFAULT: '#B45309',
                            soft: '#FEF3E0'
                        },
                        bad: {
                            DEFAULT: '#CE2C31',
                            soft: '#FDEBEC'
                        },
                    },
                    fontFamily: {
                        sans: ['Plus Jakarta Sans', 'Segoe UI', 'system-ui', 'sans-serif']
                    }
                }
            }
        };
    </script>
    {{-- The S-road logo (2026-11-16), drawn by sugo_app/tool/make_logo.py:
         SVG where the browser takes it, the .ico for the rest. --}}
    <link rel="icon" type="image/svg+xml" href="{{ asset('images/sugo-logo.svg') }}">
    <link rel="icon" href="{{ asset('favicon.ico') }}" sizes="any">
    <link rel="apple-touch-icon" href="{{ asset('images/brand-emblem.png') }}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
</head>

<body class="h-full bg-canvas font-sans text-ink antialiased">

    <div class="flex min-h-full">

        {{-- Brand panel. Hidden on small screens, where it would push the form
         below the fold on a phone. --}}
        <div class="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-gradient-to-br from-navy via-[#0A3F80] to-brand-light p-12 text-white lg:flex">
            <div class="pointer-events-none absolute -right-28 -top-28 h-96 w-96 rounded-full border-[36px] border-white/[0.05]"></div>
            <div class="absolute -right-24 -top-24 h-80 w-80 rounded-full bg-brand/25 blur-3xl"></div>
            <div class="absolute -bottom-32 -left-20 h-96 w-96 rounded-full bg-accent/15 blur-3xl"></div>

            <div class="relative flex items-center gap-3">
                {{-- The app's S-road logo (2026-11-16) - a road from a start
                     dot to a map pin, the errand SUGO is named for. Drawn by
                     sugo_app/tool/make_logo.py, the same geometry as the
                     phone's app icon. --}}
                <img src="{{ asset('images/sugo-logo.svg') }}" alt="SUGO"
                     class="h-12 w-12 shrink-0 drop-shadow-lg">
                <div>
                    <div class="text-lg font-extrabold leading-none">SUGO</div>
                    <div class="text-xs text-white/60">Fix. Technology. Appliances.</div>
                </div>
            </div>

            {{-- The S-road from the logo drawing itself in (2026-11-17): from
                 the start dot to the map pin, the errand "sugo" is named for.
                 The same geometry as sugo_app/tool/make_logo.py; drawn once,
                 then still. --}}
            <svg class="pointer-events-none absolute right-10 top-1/2 h-[26rem] w-[26rem] -translate-y-1/2 opacity-90"
                viewBox="290 170 480 660" aria-hidden="true">
                <path d="M 619.9 342.5 A 135.0 135.0 0 1 0 503.0 545.0 A 135.0 135.0 0 1 1 386.1 747.5"
                    fill="none" stroke="rgba(255,255,255,0.10)" stroke-width="112" stroke-linecap="round" />
                <path class="sugo-draw" pathLength="1"
                    d="M 619.9 342.5 A 135.0 135.0 0 1 0 503.0 545.0 A 135.0 135.0 0 1 1 386.1 747.5"
                    fill="none" stroke="#FFFFFF" stroke-width="112" stroke-linecap="round" />
                <circle class="sugo-pop" style="--d: 150ms" cx="386.1" cy="747.5" r="34" fill="#11C5E8" />
                <path class="sugo-pop" style="--d: 1650ms"
                    d="M 629.9 336.5 L 571.3 246.8 A 70.0 70.0 0 1 1 688.5 246.8 Z" fill="#F59E0B" />
                <circle class="sugo-pop" style="--d: 1750ms" cx="629.9" cy="222" r="24" fill="#FFFFFF" />
            </svg>

            <div class="relative max-w-md">
                <h2 class="sugo-rise text-3xl font-extrabold leading-tight" style="--d: 300ms">Every account is checked by a person.</h2>
                <p class="sugo-rise mt-4 text-sm leading-relaxed text-white/70" style="--d: 420ms">
                    Technicians walk into people's homes, and clients let strangers in.
                    Both submit a government ID and a selfie holding it, and neither
                    goes live until someone here has looked at both.
                </p>
            </div>

            {{-- What the console guarantees, said once each (2026-11-17). --}}
            <ul class="relative space-y-2.5 text-sm text-white/80">
                @foreach ([['id', 'A government ID and a selfie on every account'], ['clock', 'Signed links that expire: no document is ever public'], ['check', 'Every decision recorded with who made it']] as $i => [$icon, $line])
                    <li class="sugo-rise flex items-center gap-3" style="--d: {{ 600 + $i * 120 }}ms">
                        <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-white/10 ring-1 ring-white/15">
                            @include('partials.icon', ['name' => $icon, 'class' => 'h-4 w-4'])
                        </span>
                        {{ $line }}
                    </li>
                @endforeach
            </ul>

        </div>

        {{-- Form --}}
        <div class="relative flex w-full items-center justify-center overflow-hidden p-5 sm:p-8 lg:w-1/2">
            <div class="absolute -right-24 top-1/4 h-72 w-72 rounded-full bg-brand-soft/70 blur-3xl"></div>
            <div class="absolute -bottom-24 left-1/4 h-64 w-64 rounded-full bg-accent-soft/60 blur-3xl"></div>

            <div class="sugo-rise relative w-full max-w-md rounded-3xl border border-line bg-white p-6 shadow-[0_24px_70px_rgba(6,43,92,0.10)] sm:p-9">
                <div class="mb-8 flex items-center justify-between">
                    <div class="flex items-center gap-3 lg:hidden">
                        <img src="{{ asset('images/brand-emblem.png') }}" alt=""
                             class="h-10 w-10 rounded-xl object-cover ring-1 ring-brand/10">
                        <div>
                            <div class="text-base font-extrabold leading-none text-navy">SUGO</div>
                            <div class="mt-1 text-[10px] font-semibold uppercase tracking-wider text-ink-muted">Admin console</div>
                        </div>
                    </div>
                    <div class="ml-auto flex items-center gap-1.5 rounded-full bg-brand-softer px-3 py-1.5 text-[10px] font-bold uppercase tracking-wider text-brand">
                        <span class="h-1.5 w-1.5 rounded-full bg-ok"></span>
                        Secure access
                    </div>
                </div>

                <p class="mb-2 text-xs font-extrabold uppercase tracking-[0.18em] text-brand">Welcome back</p>
                <h1 class="text-2xl font-extrabold text-navy">Sign in</h1>
                <p class="mt-2 text-sm leading-relaxed text-ink-muted">Access verification, operations, and support tools for the SUGO team.</p>

                @if (session('error'))
                    <div class="mt-5 rounded-xl border border-bad/25 bg-bad-soft px-4 py-3">
                        <p class="text-sm font-semibold text-ink">{{ session('error') }}</p>
                    </div>
                @endif

                @if (session('status'))
                    <div class="mt-5 rounded-xl border border-line bg-white px-4 py-3">
                        <p class="text-sm font-semibold text-ink-muted">{{ session('status') }}</p>
                    </div>
                @endif

                <form method="POST" action="{{ route('login.store') }}" class="mt-6 space-y-4">
                    @csrf

                    <div>
                        <label for="email" class="mb-1.5 block text-xs font-bold text-ink">Email</label>
                        <input id="email" name="email" type="email" required autofocus
                            value="{{ old('email') }}" autocomplete="username"
                            class="w-full rounded-xl border border-line bg-canvas px-4 py-3 text-sm outline-none transition placeholder:text-ink-muted/60 focus:border-brand focus:bg-white focus:ring-2 focus:ring-brand/20"
                            placeholder="admin@sugo.ph">
                        @error('email')
                            <p class="mt-1.5 text-xs font-semibold text-bad">{{ $message }}</p>
                        @enderror
                    </div>

                    <div>
                        <label for="password" class="mb-1.5 block text-xs font-bold text-ink">Password</label>
                        <div class="relative">
                            <input id="password" name="password" type="password" required autocomplete="current-password"
                            class="w-full rounded-xl border border-line bg-canvas px-4 py-3 pr-12 text-sm outline-none transition placeholder:text-ink-muted/60 focus:border-brand focus:bg-white focus:ring-2 focus:ring-brand/20"
                            placeholder="••••••••">
                            <button type="button" id="toggle-password" aria-label="Show password"
                                class="absolute inset-y-0 right-0 flex w-12 items-center justify-center text-ink-muted transition hover:text-brand focus:outline-none focus:ring-2 focus:ring-inset focus:ring-brand/20">
                                <svg id="eye-open" xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12s3.5-6 9.75-6 9.75 6 9.75 6-3.5 6-9.75 6S2.25 12 2.25 12Z" />
                                    <circle cx="12" cy="12" r="2.5" />
                                </svg>
                                <svg id="eye-closed" xmlns="http://www.w3.org/2000/svg" class="hidden h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="m3 3 18 18M10.6 6.2A10.7 10.7 0 0 1 12 6c6.25 0 9.75 6 9.75 6a17.7 17.7 0 0 1-3.1 3.8M6.2 6.2C3.7 7.8 2.25 12 2.25 12a17.7 17.7 0 0 0 5.5 4.9A10.6 10.6 0 0 0 12 18c1.2 0 2.3-.2 3.3-.6" />
                                </svg>
                            </button>
                        </div>
                        @error('password')
                            <p class="mt-1.5 text-xs font-semibold text-bad">{{ $message }}</p>
                        @enderror
                    </div>

                    <button type="submit" data-loading-text="Signing in…"
                        class="mt-2 flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-brand to-brand-light px-4 py-3.5 text-sm font-bold text-white shadow-lg shadow-brand/25 transition hover:-translate-y-0.5 hover:shadow-xl hover:shadow-brand/30 focus:outline-none focus:ring-2 focus:ring-brand/40 active:translate-y-0">
                        Sign in
                    </button>
                </form>

                <div class="mt-8 flex items-center gap-3 border-t border-line pt-5 text-xs leading-relaxed text-ink-muted">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 shrink-0 text-ok" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 3 5 6v5c0 4.5 3 8.3 7 10 4-1.7 7-5.5 7-10V6l-7-3Z" />
                        <path stroke-linecap="round" stroke-linejoin="round" d="m9 12 2 2 4-4" />
                    </svg>
                    <span>Protected workspace for authorized SUGO administrators.</span>
                </div>

            </div>
        </div>
    </div>

    @include('partials.loading')
    {{-- The login has its own page skeleton, so it pulls in the motion kit
         itself (2026-11-17). --}}
    @include('partials.motion')
    <script>
        const password = document.getElementById('password');
        const togglePassword = document.getElementById('toggle-password');
        const eyeOpen = document.getElementById('eye-open');
        const eyeClosed = document.getElementById('eye-closed');

        togglePassword?.addEventListener('click', () => {
            const isHidden = password.type === 'password';
            password.type = isHidden ? 'text' : 'password';
            eyeOpen.classList.toggle('hidden', isHidden);
            eyeClosed.classList.toggle('hidden', !isHidden);
            togglePassword.setAttribute('aria-label', isHidden ? 'Hide password' : 'Show password');
        });
    </script>
</body>

</html>
