<?php

namespace App\Http\Controllers;

use App\Services\Supabase;
use Illuminate\Support\Facades\Log;
use Illuminate\View\View;
use Throwable;

class DashboardController extends Controller
{
    public function __construct(private readonly Supabase $supabase)
    {
    }

    public function __invoke(): View
    {
        // One round trip for every counter, via the `admin_dashboard_stats`
        // view. Ten separate counts would be ten HTTP calls to render one page.
        $stats = $this->supabase->first('admin_dashboard_stats') ?? [];

        $queue = $this->supabase->select('admin_verification_queue', [
            'status' => 'eq.pending',
            'order' => 'submitted_at.asc',
            'limit' => '6',
        ]);

        $recent = $this->supabase->select('admin_verification_queue', [
            'status' => 'in.(approved,rejected)',
            'order' => 'reviewed_at.desc',
            'limit' => '6',
        ]);

        // Platform analytics: jobs, ratings, device mix, the 14-day trend.
        //
        // One document from `admin_analytics()` (migration 20260921000010)
        // rather than a dozen counts. Never fatal: the verification queue is
        // the part of this page someone acts on, and a failed chart must not
        // take it down with it - the charts simply render empty.
        try {
            $analytics = $this->supabase->rpc('admin_analytics') ?? [];
        } catch (Throwable $e) {
            Log::warning('admin_analytics failed', ['error' => $e->getMessage()]);
            $analytics = [];
        }

        // The five most recent jobs still in play, for the "live work" panel.
        try {
            $liveJobs = $this->supabase->select('admin_jobs', [
                'status' => 'in.(matched,confirmed,in_progress)',
                'order' => 'created_at.desc',
                'limit' => '5',
            ]);
        } catch (Throwable $e) {
            Log::warning('admin_jobs failed', ['error' => $e->getMessage()]);
            $liveJobs = [];
        }

        return view('dashboard', compact('stats', 'queue', 'recent', 'analytics', 'liveJobs'));
    }
}
