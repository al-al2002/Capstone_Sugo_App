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

    /** The work record's private photo bucket (migration 20261122000002). */
    private const EVIDENCE_BUCKET = 'job-evidence';

    /**
     * The work record's steps, as the admin reads them. The app names the
     * first step for how the job travelled (Before / Collected / Unit
     * received); here one name covers all three.
     *
     * @var array<string, string>
     */
    public const MILESTONES = [
        'intake' => 'As found (before)',
        'diagnosis' => 'Diagnosis',
        'progress' => 'Progress',
        'after' => 'Repaired (after)',
        'handover' => 'Handover',
    ];

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

        $rows = $this->supabase->select('admin_disputes', $query);

        // Every listed booking's work record in one read, not one per report.
        $workRecords = $this->workRecords(array_column($rows, 'job_id'));

        $disputes = array_map(
            fn (array $dispute): array => $dispute + [
                'photo_urls' => $this->signedPhotos($dispute['photo_paths'] ?? []),
                'work_record' => $workRecords[$dispute['job_id']] ?? [],
            ],
            $rows,
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
                // Progressive Trust Badge (20261115000002). "Upheld" on a
                // client's report counts against the technician's Community
                // Trusted badge; the remedy drops them one level.
                'outcome' => ['nullable', 'in:upheld,not_upheld'],
                'remedy' => ['nullable', 'in:none,skill_deverification'],
                'remedy_specialization' => [
                    'nullable',
                    'required_if:remedy,skill_deverification',
                    'in:computer,phone_tablet,network_setup,appliance,pc_building',
                ],
            ],
            [
                'note.required' => 'Write the decision out - both sides are shown it word for word.',
                'note.min' => 'Write the decision out - both sides are shown it word for word.',
                'remedy_specialization.required_if' => 'Choose which specialization the de-verification removes.',
            ],
        );

        // "Close without action" is never upheld and carries no remedy; the
        // database enforces the same, this just keeps the form honest.
        $dismissed = $data['decision'] === 'dismissed';
        $remedy = $dismissed ? 'none' : ($data['remedy'] ?? 'none');

        try {
            $this->supabase->rpc('resolve_job_dispute', [
                'p_dispute_id' => $id,
                'p_decision' => $data['decision'],
                'p_note' => trim($data['note']),
                'p_admin_id' => session('admin.id'),
                'p_outcome' => $dismissed ? 'not_upheld' : ($data['outcome'] ?? 'upheld'),
                'p_remedy' => $remedy,
                'p_remedy_specialization' => $remedy === 'skill_deverification'
                    ? $data['remedy_specialization']
                    : null,
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
    private function signedPhotos(array $paths, string $bucket = self::PHOTO_BUCKET): array
    {
        $urls = [];
        foreach ($paths as $path) {
            $url = $this->supabase->signedUrl($path, null, $bucket);
            if ($url !== null) {
                $urls[] = $url;
            }
        }

        return $urls;
    }

    /**
     * The work record of each booking: the checkpoint photos its technician
     * took during the job, oldest first, keyed by job id. Evidence the admin
     * weighs beside the report. A failed read (for example before migration
     * 20261122000002 is applied) shows no record rather than failing the page.
     *
     * @param  array<int, string>  $jobIds
     * @return array<string, array<int, array<string, mixed>>>
     */
    private function workRecords(array $jobIds): array
    {
        $jobIds = array_values(array_unique(array_filter($jobIds)));
        if ($jobIds === []) {
            return [];
        }

        try {
            $rows = $this->supabase->select('job_evidence', [
                'select' => 'job_id,milestone,photo_paths,note,latitude,longitude,captured_at',
                'job_id' => 'in.('.implode(',', $jobIds).')',
                'order' => 'captured_at.asc',
            ]);
        } catch (RuntimeException) {
            return [];
        }

        $records = [];
        foreach ($rows as $row) {
            $records[$row['job_id']][] = $row + [
                'label' => self::MILESTONES[$row['milestone']] ?? $row['milestone'],
                'photo_urls' => $this->signedPhotos($row['photo_paths'] ?? [], self::EVIDENCE_BUCKET),
            ];
        }

        return $records;
    }
}
