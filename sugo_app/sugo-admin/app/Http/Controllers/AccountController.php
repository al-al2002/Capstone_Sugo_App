<?php

namespace App\Http\Controllers;

use App\Services\Supabase;
use Illuminate\Http\Request;
use Illuminate\View\View;

/**
 * Browsing technicians and clients.
 *
 * Read-only on purpose. Everything that changes an account's standing -
 * activation, verification tier, trust level - is a consequence of a review
 * decision, and is made by a Postgres function that enforces the conditions.
 * A free-form "edit account" screen here would be a way around all of it.
 */
class AccountController extends Controller
{
    public function __construct(private readonly Supabase $supabase)
    {
    }

    public function index(Request $request, string $role): View
    {
        abort_unless(in_array($role, ['technician', 'client'], true), 404);

        $status = $request->query('status', 'all');

        $query = [
            'role' => 'eq.'.$role,
            'order' => 'created_at.desc',
            'limit' => '200',
        ];

        if (in_array($status, ['incomplete', 'pending_review', 'active', 'rejected'], true)) {
            $query['registration_status'] = 'eq.'.$status;
        } else {
            $status = 'all';
        }

        $rows = $this->supabase->select('admin_applicant_detail', $query);

        $counts = [
            'all' => $this->supabase->count('profiles', ['role' => 'eq.'.$role]),
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

        return view('accounts.index', compact('rows', 'role', 'status', 'counts'));
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

        if ($role === 'technician') {
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
        ));
    }
}
