<?php

namespace App\Http\Controllers;

use App\Services\Supabase;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\View\View;
use RuntimeException;

class AuthController extends Controller
{
    public function __construct(private readonly Supabase $supabase)
    {
    }

    public function create(Request $request): View|RedirectResponse
    {
        if ($request->session()->has('admin')) {
            return redirect()->route('dashboard');
        }

        return view('auth.login');
    }

    /**
     * Signs an administrator in against Supabase Auth.
     *
     * Throttled by email + IP. Without a limit, this form is an offline-speed
     * password oracle against a known address - and `admin@sugo.ph` is not
     * exactly hard to guess. Five attempts a minute keeps a mistyped password
     * painless while making a search useless.
     */
    public function store(Request $request): RedirectResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $throttleKey = mb_strtolower($credentials['email']).'|'.$request->ip();

        if (RateLimiter::tooManyAttempts($throttleKey, 5)) {
            $seconds = RateLimiter::availableIn($throttleKey);

            return back()
                ->withInput($request->only('email'))
                ->with('error', "Too many attempts. Try again in {$seconds} seconds.");
        }

        try {
            $admin = $this->supabase->signInAdmin(
                $credentials['email'],
                $credentials['password'],
            );
        } catch (RuntimeException $e) {
            // A configuration fault, not a bad password. Saying so saves the
            // operator from hunting for a typo in a password that was fine.
            return back()
                ->withInput($request->only('email'))
                ->with('error', $e->getMessage());
        }

        if ($admin === null) {
            RateLimiter::hit($throttleKey, 60);

            // One message for a wrong password, an unknown address, and a
            // valid non-admin account alike. Distinguishing them would let
            // anyone enumerate which emails have accounts, and would confirm
            // to a technician that their credentials work here.
            return back()
                ->withInput($request->only('email'))
                ->with('error', 'Those credentials do not match an administrator account.');
        }

        RateLimiter::clear($throttleKey);

        // Rotate the session id so a token captured before login cannot be
        // replayed against the authenticated session.
        $request->session()->regenerate();
        $request->session()->put('admin', $admin);

        return redirect()->intended(route('dashboard'));
    }

    public function destroy(Request $request): RedirectResponse
    {
        $request->session()->forget('admin');
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login')->with('status', 'Signed out.');
    }
}
