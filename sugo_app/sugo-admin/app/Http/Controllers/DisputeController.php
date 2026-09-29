<?php

namespace App\Http\Controllers;

use App\Services\Supabase;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;
use RuntimeException;

/**
 * Problems reported on bookings, and the admin's decision on each.
 *
 * Reads the `admin_disputes` view (migration 20260928000001), which names
 * both people on the job and is granted to `service_role` only. Decisions go
 * through `resolve_job_dispute()` rather than a direct write, so the rules -
 * a decision needs a written reason, only an admin may decide, an already
 * decided report cannot be decided again - live in one place, in SQL.
 *
 * The decision note is shown word for word to both the client and the
 * technician on the booking, in the app.
 */
class DisputeController extends Controller
{
    /** @var array<string, string> Filter key => label. */
    public const FILTERS = [
        'open' => 'Open',
        'decided' => 'Decided',
        'all' => 'All',
    ];

    private const PHOTO_BUCKET = 'dispute-photos';

    public function __construct(private readonly Supabase $supabase) {}

    public function index(Request $request): View
    {
        $filter = (string) $request->query('status', 'open');
        if (! array_key_exists($filter, self::FILTERS)) {
            $filter = 'open';
        }

        $query = ['order' => 'created_at.desc', 'limit' => '200'];
        $query += match ($filter) {
            'open' => ['status' => 'eq.open'],
            'decided' => ['status' => 'in.(resolved,dismissed)'],
            default => [],
        };

        $disputes = array_map(
            fn (array $dispute): array => $dispute + [
                'photo_urls' => $this->signedPhotos($dispute['photo_paths'] ?? []),
            ],
            $this->supabase->select('admin_disputes', $query),
        );

        $counts = [
            'open' => $this->supabase->count('admin_disputes', ['status' => 'eq.open']),
            'decided' => $this->supabase->count('admin_disputes', ['status' => 'in.(resolved,dismissed)']),
        ];
        $counts['all'] = $counts['open'] + $counts['decided'];

        return view('disputes.index', compact('disputes', 'filter', 'counts'));
    }

    public function update(Request $request, string $id): RedirectResponse
    {
        // A malformed id is not a real report, so it is a 404 rather than a
        // cast error surfacing from PostgREST as a 500.
        abort_unless(
            (bool) preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id),
            404,
        );

        $data = $request->validate(
            [
                'decision' => ['required', 'in:resolved,dismissed'],
                'note' => ['required', 'string', 'min:5', 'max:2000'],
            ],
            [
                'note.required' => 'Write the decision out - both sides are shown it word for word.',
                'note.min' => 'Write the decision out - both sides are shown it word for word.',
            ],
        );

        try {
            $this->supabase->rpc('resolve_job_dispute', [
                'p_dispute_id' => $id,
                'p_decision' => $data['decision'],
                'p_note' => trim($data['note']),
                'p_admin_id' => session('admin.id'),
            ]);
        } catch (RuntimeException $e) {
            return back()->withInput()->with('error', $e->getMessage());
        }

        return redirect()
            ->route('disputes.index')
            ->with('status', $data['decision'] === 'resolved'
                ? 'Resolved. Both people on the booking can now read your decision in the app.'
                : 'Closed. Both people on the booking can now read your reason in the app.');
    }

    /**
     * Signed, short-lived URLs for a report's photos. An unreadable photo is
     * skipped rather than failing the page.
     *
     * @param  array<int, string>  $paths
     * @return array<int, string>
     */
    private function signedPhotos(array $paths): array
    {
        $urls = [];
        foreach ($paths as $path) {
            $url = $this->supabase->signedUrl($path, null, self::PHOTO_BUCKET);
            if ($url !== null) {
                $urls[] = $url;
            }
        }

        return $urls;
    }
}
