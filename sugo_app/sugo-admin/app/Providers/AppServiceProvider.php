<?php

namespace App\Providers;

use App\Services\Supabase;
use Illuminate\Support\Facades\View;
use Illuminate\Support\ServiceProvider;
use Throwable;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        /*
         * The sidebar's "ID review" badge.
         *
         * The layout has always rendered `$pendingBadge`, but nothing ever set
         * it - so the one number that says "people are waiting on you" never
         * appeared on any page. A composer puts it on every page that uses the
         * layout without each controller having to remember.
         *
         * Only for a signed-in admin (the login page uses its own view), and
         * never fatal: a badge is a convenience, and a Supabase hiccup must not
         * take down the page it decorates.
         */
        View::composer('layouts.app', function ($view): void {
            if (! session()->has('admin')) {
                return;
            }

            try {
                $count = app(Supabase::class)->count('identity_verifications', [
                    'status' => 'eq.pending',
                ]);
            } catch (Throwable) {
                $count = 0;
            }

            // Reports still waiting on a decision - the "Disputes" badge.
            try {
                $disputes = app(Supabase::class)->count('admin_disputes', [
                    'status' => 'eq.open',
                ]);
            } catch (Throwable) {
                $disputes = 0;
            }

            $view->with('pendingBadge', $count)->with('disputeBadge', $disputes);
        });
    }
}
