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
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
</head>

<body class="h-full bg-canvas font-sans text-ink antialiased">

    <div class="flex min-h-full">

        {{-- Brand panel. Hidden on small screens, where it would push the form
         below the fold on a phone. --}}
        <div class="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-navy p-12 text-white lg:flex">
            <div class="absolute -right-24 -top-24 h-80 w-80 rounded-full bg-brand/25 blur-3xl"></div>
            <div class="absolute -bottom-32 -left-20 h-96 w-96 rounded-full bg-accent/15 blur-3xl"></div>

            <div class="relative flex items-center gap-3">
                {{-- The app icon's emblem (house, wrench, van), the same file
                     the mobile app uses - see tool/prepare_brand_images.py. --}}
                <img src="{{ asset('images/brand-emblem.png') }}" alt=""
                     class="h-10 w-10 rounded-xl object-cover ring-1 ring-white/20">
                <div>
                    <div class="text-lg font-extrabold leading-none">SUGO</div>
                    <div class="text-xs text-white/60">Fix. Technology. Appliances.</div>
                </div>
            </div>

            <div class="relative max-w-md">
                <h2 class="text-3xl font-extrabold leading-tight">Every account is checked by a person.</h2>
                <p class="mt-4 text-sm leading-relaxed text-white/70">
                    Technicians walk into people's homes, and clients let strangers in.
                    Both submit a government ID and a selfie holding it, and neither
                    goes live until someone here has looked at both.
                </p>
            </div>

            <p class="relative text-xs text-white/40"></p>
        </div>

        {{-- Form --}}
        <div class="flex w-full items-center justify-center p-6 lg:w-1/2">
            <div class="w-full max-w-sm">
                <div class="mb-8 lg:hidden">
                    <div class="flex items-center gap-2">
                        <img src="{{ asset('images/brand-emblem.png') }}" alt=""
                             class="h-9 w-9 rounded-lg object-cover">
                        <span class="text-lg font-extrabold text-navy">SUGO</span>
                    </div>
                </div>

                <h1 class="text-2xl font-extrabold text-navy">Sign in</h1>
                <p class="mt-1 text-sm text-ink-muted">Administrator accounts only.</p>

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
                            class="w-full rounded-xl border border-line bg-white px-4 py-3 text-sm outline-none transition focus:border-brand focus:ring-2 focus:ring-brand/20"
                            placeholder="admin@sugo.ph">
                        @error('email')
                            <p class="mt-1.5 text-xs font-semibold text-bad">{{ $message }}</p>
                        @enderror
                    </div>

                    <div>
                        <label for="password" class="mb-1.5 block text-xs font-bold text-ink">Password</label>
                        <input id="password" name="password" type="password" required autocomplete="current-password"
                            class="w-full rounded-xl border border-line bg-white px-4 py-3 text-sm outline-none transition focus:border-brand focus:ring-2 focus:ring-brand/20"
                            placeholder="••••••••">
                        @error('password')
                            <p class="mt-1.5 text-xs font-semibold text-bad">{{ $message }}</p>
                        @enderror
                    </div>

                    <button type="submit" data-loading-text="Signing in…"
                        class="w-full rounded-xl bg-brand px-4 py-3 text-sm font-bold text-white transition hover:bg-brand-dark focus:outline-none focus:ring-2 focus:ring-brand/40">
                        Sign in
                    </button>
                </form>


            </div>
        </div>
    </div>

    @include('partials.loading')
</body>

</html>
