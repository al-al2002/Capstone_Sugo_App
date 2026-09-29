<?php

use App\Http\Controllers\AccountController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\DisputeController;
use App\Http\Controllers\JobController;
use App\Http\Controllers\VerificationController;
use App\Http\Middleware\EnsureAdmin;
use Illuminate\Support\Facades\Route;

/*
| SUGO review console
|
| Every route except sign-in is behind `EnsureAdmin`. The panel reads Supabase
| with the service role key, which bypasses all RLS - so the session check is
| the only thing standing between an anonymous request and every identity
| document on the platform. It is applied to the group rather than per-route so
| a new screen cannot be added without it.
*/

Route::get('/login', [AuthController::class, 'create'])->name('login');
Route::post('/login', [AuthController::class, 'store'])->name('login.store');
Route::post('/logout', [AuthController::class, 'destroy'])->name('logout');

Route::middleware(EnsureAdmin::class)->group(function (): void {
    Route::get('/', DashboardController::class)->name('dashboard');

    // Every job, with both parties named and its progress. Inside the group
    // like everything else: `admin_jobs` is service-role only and returns
    // every job on the platform.
    Route::get('/jobs', [JobController::class, 'index'])->name('jobs.index');
    Route::get('/jobs/{id}', [JobController::class, 'show'])->name('jobs.show');

    // Problems reported on bookings, and the decision on each. The decision
    // is shown to both people on the booking, so it goes through an RPC that
    // insists on a written reason.
    Route::get('/disputes', [DisputeController::class, 'index'])->name('disputes.index');
    Route::post('/disputes/{id}', [DisputeController::class, 'update'])->name('disputes.update');

    Route::get('/verifications', [VerificationController::class, 'index'])
        ->name('verifications.index');
    Route::get('/verifications/{id}', [VerificationController::class, 'show'])
        ->name('verifications.show');
    Route::post('/verifications/{id}', [VerificationController::class, 'update'])
        ->name('verifications.update');

    Route::get('/accounts/{role}', [AccountController::class, 'index'])
        ->name('accounts.index');
    Route::get('/accounts/{role}/{id}', [AccountController::class, 'show'])
        ->name('accounts.show');
});
