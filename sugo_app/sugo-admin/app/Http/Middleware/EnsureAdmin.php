<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Blocks every console route unless the session belongs to a signed-in admin.
 *
 * The session key is written only by `AuthController::store`, which sets it
 * after Supabase has accepted the password AND the profile has been confirmed
 * as `role = 'admin'`. Both halves matter: a technician's own credentials are
 * valid against the same Auth instance, so a password check alone would let
 * them in here.
 */
class EnsureAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->session()->has('admin')) {
            return redirect()
                ->route('login')
                ->with('error', 'Please sign in to continue.');
        }

        return $next($request);
    }
}
