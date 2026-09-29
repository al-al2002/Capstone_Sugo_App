<?php

namespace App\Http\Controllers;

use App\Services\Supabase;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Every job on the platform: who posted it, who is doing it, how far it has
 * got, and how it was rated.
 *
 * Reads the `admin_jobs` view (migration 20260921000010), which resolves both
 * names server-side. That view is granted to `service_role` only - it joins
 * `auth.users` for the client's email and returns every job on the platform -
 * which is exactly why it can only be reached through this console, behind
 * `EnsureAdmin`.
 */
class JobController extends Controller
{
    /** Statuses that mean the job is still in play. */
    private const ACTIVE = ['pending', 'matched', 'confirmed', 'in_progress'];

    public function __construct(private readonly Supabase $supabase)
    {
    }

    public function index(Request $request): View
    {
        $filter = $request->query('status', 'active');
        if (! in_array($filter, ['active', 'completed', 'cancelled', 'all'], true)) {
            $filter = 'active';
        }

        $query = [
            'order' => 'created_at.desc',
            'limit' => '200',
        ];

        $query += match ($filter) {
            'active' => ['status' => 'in.('.implode(',', self::ACTIVE).')'],
            'completed' => ['status' => 'eq.completed'],
            'cancelled' => ['status' => 'eq.cancelled'],
            default => [],
        };

        // Search by either person's name or the fault.
        //
        // The term goes into a PostgREST `or=(...)` filter, where commas,
        // parentheses and asterisks are syntax. They are stripped rather than
        // escaped: a name never needs them, and passing them through would let
        // a search box rewrite the filter it sits inside.
        $search = trim((string) $request->query('q', ''));
        $safe = trim(preg_replace('/[^\pL\pN\s\.\-\']/u', '', $search) ?? '');
        if ($safe !== '') {
            $term = '*'.$safe.'*';
            $query['or'] = '(client_name.ilike.'.$term
                .',technician_name.ilike.'.$term
                .',problem_symptom.ilike.'.$term.')';
        }

        $jobs = $this->supabase->select('admin_jobs', $query);

        $counts = [
            'active' => $this->supabase->count('jobs', ['status' => 'in.('.implode(',', self::ACTIVE).')']),
            'completed' => $this->supabase->count('jobs', ['status' => 'eq.completed']),
            'cancelled' => $this->supabase->count('jobs', ['status' => 'eq.cancelled']),
        ];
        $counts['all'] = array_sum($counts);

        return view('jobs.index', compact('jobs', 'filter', 'counts', 'search'));
    }

    public function show(string $id): View
    {
        // A malformed id would reach PostgREST as a cast error and surface as a
        // 500. It is not a real job, so it is a 404.
        abort_unless(
            (bool) preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id),
            404,
        );

        $job = $this->supabase->first('admin_jobs', ['id' => 'eq.'.$id]);

        abort_if($job === null, 404);

        return view('jobs.show', compact('job'));
    }
}
