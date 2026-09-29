<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Tells an applicant their account is live and they can sign in.
 *
 * ## Sent on activation, not on approval
 *
 * These are not the same moment. `review_applicant()` clears the identity, but
 * an account only becomes `active` once every other required step is done too -
 * a technician still owes a passed assessment and a clearance, a client still
 * owes an address. Approving the ID of someone with steps left does not let
 * them in, so telling them "you can now log in" would be a lie they would
 * discover at the login screen.
 *
 * The controller therefore sends this only when the review actually flipped
 * `registration_status` to `active`.
 *
 * ## Why this lives in the admin app
 *
 * Supabase's SMTP settings belong to GoTrue and only carry auth mail - magic
 * links, OTP codes, password resets. There is no way to ask it to send an
 * arbitrary message. The admin app already has Laravel's mailer and is already
 * the thing performing the approval, so the notification is sent from the same
 * place as the decision rather than through a new edge function and a second
 * copy of the mail credentials.
 */
class AccountApproved extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $fullName,
        public string $role,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Your SUGO account is approved',
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.account-approved',
            with: [
                'name' => $this->firstName(),
                // Drives one paragraph, because what the two roles can do next
                // is genuinely different: a technician starts receiving job
                // offers, a client starts booking.
                'isTechnician' => $this->role === 'technician',
            ],
        );
    }

    /**
     * First name only.
     *
     * "Hi Juan" reads like a person wrote it; "Hi Juan Dela Cruz" reads like a
     * database did. Falls back to the whole string when there is no space to
     * split on, which covers single-word names rather than producing an empty
     * greeting.
     */
    private function firstName(): string
    {
        $trimmed = trim($this->fullName);

        if ($trimmed === '') {
            return 'there';
        }

        $first = strtok($trimmed, ' ');

        return $first === false ? $trimmed : $first;
    }
}
