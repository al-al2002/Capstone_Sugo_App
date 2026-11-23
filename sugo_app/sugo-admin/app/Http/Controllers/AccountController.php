<?php

namespace App\Http\Controllers;

use App\Services\Supabase;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Browsing technicians and clients.
 *
 * Read-only on purpose. Everything that changes an account's standing -
 * activation, verification tier, trust level - is a consequence of a review
 * decision, and is made by a Postgres function that enforces the conditions.
 * A free-form "edit account" screen here would be a way around all of it.
 *
 * ## Pending accounts live in ID review (2026-11-17)
 *
 * An account awaiting review is not listed here. It is work waiting for a
 * decision, and the decision is made in ID review, so that is where it is
 * listed - the user's call. The lists show the accounts that are decided or
 * still registering, and say how many are waiting, with a way there.
 */
class AccountController extends Controller
{
    public function __construct(private readonly Supabase $supabase) {}

    public function index(Request $request, string $role): View|RedirectResponse
    {
        abort_unless(in_array($role, ['technician', 'client'], true), 404);

        $status = $request->query('status', 'all');

        // An old "Awaiting review" link: those accounts are in ID review now.
        if ($status === 'pending_review') {
            return redirect()->route('verifications.index', ['role' => $role]);
        }

        $query = [
            'role' => 'eq.'.$role,
            'order' => 'created_at.desc',
            'limit' => '200',
        ];

        if (in_array($status, ['incomplete', 'active', 'rejected'], true)) {
            $query['registration_status'] = 'eq.'.$status;
        } else {
            $status = 'all';
            // Everyone but the accounts awaiting review - see the header.
            $query['registration_status'] = 'neq.pending_review';
        }

        $rows = $this->supabase->select('admin_applicant_detail', $query);

        // The work each technician takes (2026-11-17), in one read keyed by
        // id rather than a query per row.
        $workTypes = $role === 'technician' ? $this->workTypes($rows) : [];

        $counts = [
            'all' => $this->supabase->count('profiles', [
                'role' => 'eq.'.$role, 'registration_status' => 'neq.pending_review',
            ]),
            'incomplete' => $this->supabase->count('profiles', [
                'role' => 'eq.'.$role, 'registration_status' => 'eq.incomplete',
            ]),
            'pending_review' => $this->supabase->count('profiles', [
                'role' => 'eq.'.$role, 'registration_status' => 'eq.pending_review',
            ]),
            'active' => $this->supabase->count('profiles', [
                'role' => 'eq.'.$role, 'registration_status' => 'eq.active',
            ]),
            'rejected' => $this->supabase->count('profiles', [
                'role' => 'eq.'.$role, 'registration_status' => 'eq.rejected',
            ]),
        ];

        return view('accounts.index', compact('rows', 'role', 'status', 'counts', 'workTypes'));
    }

    /**
     * `technicians` rows for these accounts - work type and shop - keyed by id.
     *
     * @param  list<array<string,mixed>>  $rows
     * @return array<string,array<string,mixed>>
     */
    private function workTypes(array $rows): array
    {
        $ids = array_values(array_filter(array_map(
            fn (array $row): ?string => $row['user_id'] ?? null,
            $rows,
        )));

        if ($ids === []) {
            return [];
        }

        $technicians = $this->supabase->select('technicians', [
            'select' => 'id,offers_home_service,offers_shop_repair,shop_name,shop_latitude,shop_longitude,rain_travel,heavy_traffic_travel',
            'id' => 'in.('.implode(',', $ids).')',
        ]);

        $byId = [];
        foreach ($technicians as $technician) {
            $byId[$technician['id']] = $technician;
        }

        return $byId;
    }

    public function show(string $role, string $id): View
    {
        abort_unless(in_array($role, ['technician', 'client'], true), 404);

        $account = $this->supabase->first('admin_applicant_detail', [
            'user_id' => 'eq.'.$id,
        ]);

        abort_if($account === null, 404);

        $verifications = $this->supabase->select('admin_verification_queue', [
            'user_id' => 'eq.'.$id,
            'order' => 'submitted_at.desc',
        ]);

        $specializations = [];
        $documents = [];
        $addresses = [];
        $work = null;

        if ($role === 'technician') {
            // Home Service, Shop Repair or both, and the shop (2026-11-17).
            $work = $this->workTypes([$account])[$id] ?? null;

            $specializations = $this->supabase->select('technician_specializations', [
                'technician_id' => 'eq.'.$id,
                'order' => 'created_at.asc',
            ]);

            $documents = $this->supabase->select('technician_verification_documents', [
                'technician_id' => 'eq.'.$id,
                'order' => 'uploaded_at.desc',
            ]);
        } else {
            $addresses = $this->supabase->select('client_saved_addresses', [
                'client_id' => 'eq.'.$id,
                'order' => 'is_default.desc',
            ]);
        }

        return view('accounts.show', compact(
            'account',
            'role',
            'verifications',
            'specializations',
            'documents',
            'addresses',
            'work',
        ));
    }
}
