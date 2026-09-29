<?php

namespace App\Http\Controllers;

use App\Mail\AccountApproved;
use App\Services\Supabase;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\View\View;
use RuntimeException;

/**
 * The review queue: the reason this panel exists.
 *
 * A reviewer sees the government ID and the selfie holding it side by side,
 * decides whether they show the same person, and approves or rejects. That
 * decision is what turns a registration into a usable SUGO account.
 */
class VerificationController extends Controller
{
    public function __construct(private readonly Supabase $supabase)
    {
    }

    public function index(Request $request): View
    {
        $status = $request->query('status', 'pending');

        if (! in_array($status, ['pending', 'approved', 'rejected', 'all'], true)) {
            $status = 'pending';
        }

        $query = [
            // Pending oldest-first: someone who has waited two days should be
            // seen before someone who submitted a minute ago. Decided rows go
            // newest-first, because that list is read as history.
            'order' => $status === 'pending' ? 'submitted_at.asc' : 'reviewed_at.desc',
            'limit' => '100',
        ];

        // Clients and technicians are reviewed against different bars - a
        // technician also brings credentials that ride on the same decision -
        // so a reviewer often wants to work through one kind at a time.
        $role = $request->query('role', 'all');

        if (! in_array($role, ['all', 'technician', 'client'], true)) {
            $role = 'all';
        }

        if ($status !== 'all') {
            $query['status'] = 'eq.'.$status;
        }

        if ($role !== 'all') {
            $query['role'] = 'eq.'.$role;
        }

        $rows = $this->supabase->select('admin_verification_queue', $query);

        $counts = [
            'pending' => $this->supabase->count('identity_verifications', ['status' => 'eq.pending']),
            'approved' => $this->supabase->count('identity_verifications', ['status' => 'eq.approved']),
            'rejected' => $this->supabase->count('identity_verifications', ['status' => 'eq.rejected']),
        ];

        // Role counts follow the status tab, so "Technicians (3)" under
        // Waiting means three technicians are waiting - not three ever.
        $scope = $status === 'all' ? [] : ['status' => 'eq.'.$status];
        $technicians = $this->supabase->count('identity_verifications', $scope + ['role' => 'eq.technician']);
        $clients = $this->supabase->count('identity_verifications', $scope + ['role' => 'eq.client']);

        $roleCounts = [
            'all' => $technicians + $clients,
            'technician' => $technicians,
            'client' => $clients,
        ];

        return view('verifications.index', compact('rows', 'status', 'counts', 'role', 'roleCounts'));
    }

    public function show(string $id): View
    {
        $verification = $this->supabase->first('admin_verification_queue', [
            'verification_id' => 'eq.'.$id,
        ]);

        abort_if($verification === null, 404);

        $applicant = $this->supabase->first('admin_applicant_detail', [
            'user_id' => 'eq.'.$verification['user_id'],
        ]) ?? [];

        // Short-lived signed URLs. The bucket is private, so these are the only
        // way to render the images, and they expire in minutes so a link left
        // in browser history is dead long before anyone could reuse it.
        $idUrl = $this->supabase->signedUrl($verification['id_document_url'] ?? null);
        $selfieUrl = $this->supabase->signedUrl($verification['selfie_with_id_url'] ?? null);

        // Earlier attempts, so a repeat rejection is visible rather than a
        // surprise. A third submission from the same person is a different
        // judgement call from a first.
        $history = $this->supabase->select('admin_verification_queue', [
            'user_id' => 'eq.'.$verification['user_id'],
            'order' => 'submitted_at.desc',
        ]);

        $specializations = [];
        $documents = [];

        if (($verification['role'] ?? null) === 'technician') {
            $specializations = $this->supabase->select('technician_specializations', [
                'technician_id' => 'eq.'.$verification['user_id'],
                'order' => 'created_at.asc',
            ]);

            $documents = $this->supabase->select('technician_verification_documents', [
                'technician_id' => 'eq.'.$verification['user_id'],
                'order' => 'uploaded_at.desc',
            ]);

            // Credentials are reviewed on this same screen, so their previews
            // have to be resolvable here. Portfolio images live in the public
            // job-photos bucket and already carry a full URL; certificates and
            // NBI clearances are private and need signing exactly like an
            // identity document.
            foreach ($documents as $index => $document) {
                $documents[$index]['preview_url'] = $document['doc_type'] === 'portfolio'
                    ? $document['file_url']
                    : $this->supabase->signedUrl($document['file_url']);
            }
        }

        return view('verifications.show', compact(
            'verification',
            'applicant',
            'idUrl',
            'selfieUrl',
            'history',
            'specializations',
            'documents',
        ));
    }

    /**
     * Records the whole decision - identity and credentials - in one call.
     *
     * Goes through `review_applicant()` rather than updating tables directly.
     * That function holds the rules a direct write would skip:
     *
     *  - a rejection must carry a reason the applicant can act on
     *  - an approval activates the account only if the rest of registration is
     *    already finished; otherwise it leaves the status alone so the person
     *    can carry on where they left off
     *  - a technician's `is_verified` is set only when both conditions hold
     *  - the identity is decided before the credentials, so an approved
     *    certificate can promote a newly-active technician to `certified_pro`
     *
     * It is also atomic. Approving the identity and then failing on the third
     * certificate would otherwise put a technician live claiming a credential
     * nobody ruled on.
     */
    /**
     * Ids of the credentials still awaiting a verdict for this applicant.
     *
     * Read fresh at decision time rather than carried through the form, so the
     * set approved is exactly the set that is still pending when the button is
     * pressed.
     *
     * @return array<int,string>
     */
    private function pendingDocuments(string $verificationId): array
    {
        $verification = $this->supabase->first('identity_verifications', [
            'id' => 'eq.'.$verificationId,
            'select' => 'user_id,role',
        ]);

        if (($verification['role'] ?? null) !== 'technician') {
            return [];
        }

        $documents = $this->supabase->select('technician_verification_documents', [
            'technician_id' => 'eq.'.$verification['user_id'],
            'status' => 'eq.pending',
            'select' => 'id',
        ]);

        return array_column($documents, 'id');
    }

    public function update(Request $request, string $id): RedirectResponse
    {
        $data = $request->validate([
            'decision' => ['required', 'in:approve,reject'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]);

        $approved = $data['decision'] === 'approve';
        $notes = trim((string) ($data['notes'] ?? ''));

        // One decision covers the ID and every credential attached to it.
        //
        // The credential list is built HERE, from the database, rather than
        // from the form. The review screen shows the uploads but offers no
        // controls over them, so there is nothing to read off the request -
        // and building it server-side means a crafted POST cannot approve a
        // credential the reviewer never saw.
        //
        // Approving takes the credentials with it. Rejecting deliberately does
        // not: the applicant will resubmit their ID, and wiping their
        // certificates at the same time would force them to re-upload
        // everything to fix one blurred photo. They stay pending and are
        // decided on the next pass.
        $documents = [];

        if ($approved) {
            foreach ($this->pendingDocuments($id) as $documentId) {
                $documents[] = ['id' => $documentId, 'decision' => 'approve'];
            }
        }

        // Checked here as well as in SQL so the reviewer gets the message
        // beside the form they are filling in, rather than a database error.
        if (! $approved && $notes === '') {
            return back()->withInput()->with(
                'error',
                'A rejection needs a reason. The applicant is shown it word for word.',
            );
        }

        try {
            $result = $this->supabase->rpc('review_applicant', [
                'p_verification_id' => $id,
                'p_approved' => $approved,
                'p_reviewer_id' => session('admin.id'),
                'p_notes' => $notes === '' ? null : $notes,
                'p_documents' => $documents,
            ]);
        } catch (RuntimeException $e) {
            return back()->withInput()->with('error', $e->getMessage());
        }

        $identity = is_array($result) ? ($result['identity'] ?? []) : [];
        $status = is_array($identity) ? ($identity['registration_status'] ?? null) : null;

        // Only an account that actually went active gets told it can log in.
        // Approving the ID of someone with steps left does not admit them, so
        // the mail would be a promise the login screen then breaks.
        if ($approved && $status === 'active') {
            $this->notifyApproved(
                is_array($result) ? ($result['user_id'] ?? null) : null,
            );
        }

        $message = $approved
            ? ($status === 'active'
                ? 'Approved. The account is now active.'
                : 'Approved. Their ID is cleared, and the account activates once they finish the remaining steps.')
            : 'Rejected. They can retake their photos and submit again.';

        // Say what happened to the credentials too, so a reviewer who ticked
        // through them quickly can see the decision actually landed.
        $approvedDocs = is_array($result) ? (int) ($result['documents_approved'] ?? 0) : 0;
        $rejectedDocs = is_array($result) ? (int) ($result['documents_rejected'] ?? 0) : 0;

        if ($approvedDocs > 0) {
            $message .= ' '.$approvedDocs.' credential'
                .($approvedDocs === 1 ? '' : 's').' approved with it.';
        } elseif (! $approved && $rejectedDocs === 0) {
            // Said out loud so a reviewer does not assume a rejection also
            // threw away the uploads.
            $message .= ' Their credentials are untouched.';
        }

        return redirect()->route('verifications.index')->with('status', $message);
    }

    /**
     * Emails a newly activated applicant that they can sign in.
     *
     * Never fatal. A reviewer's decision has already been written to the
     * database by the time this runs, and a mail server that is down must not
     * turn a completed approval into an error page - the reviewer would retry
     * a decision that already landed.
     */
    private function notifyApproved(?string $userId): void
    {
        if ($userId === null) {
            return;
        }

        try {
            $applicant = $this->supabase->first('admin_applicant_detail', [
                'user_id' => 'eq.'.$userId,
            ]);

            $email = is_array($applicant) ? ($applicant['email'] ?? null) : null;

            if (! is_string($email) || $email === '') {
                Log::warning('Approved applicant has no email address', [
                    'user_id' => $userId,
                ]);

                return;
            }

            Mail::to($email)->send(new AccountApproved(
                fullName: (string) ($applicant['full_name'] ?? ''),
                role: (string) ($applicant['role'] ?? ''),
            ));
        } catch (\Throwable $e) {
            // Logged rather than surfaced: see the note above.
            Log::error('Could not send the approval email', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
