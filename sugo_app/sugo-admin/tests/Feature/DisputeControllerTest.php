<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class DisputeControllerTest extends TestCase
{
    private const BASE = 'https://project.supabase.test';

    private const ADMIN_ID = '11111111-1111-4111-8111-111111111111';

    private const DISPUTE_ID = '22222222-2222-4222-8222-222222222222';

    private const JOB_ID = '33333333-3333-4333-8333-333333333333';

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'supabase.url' => self::BASE,
            'supabase.service_role_key' => 'test-service-key',
        ]);
    }

    /** @return array<string, array<string, string>> */
    private function signedIn(): array
    {
        return ['admin' => ['id' => self::ADMIN_ID, 'name' => 'Ana Admin', 'email' => 'ana@sugo.app']];
    }

    /**
     * Supabase as the index page and the layout's badges read it: a list of
     * reports, counts through Content-Range, and one signed photo URL.
     */
    private function fakeReadEndpoints(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            self::BASE.'/rest/v1/admin_disputes*' => function (Request $request) {
                if ($request->hasHeader('Prefer', 'count=exact')) {
                    return Http::response('', 200, ['Content-Range' => '0-0/1']);
                }

                return Http::response([[
                    'id' => self::DISPUTE_ID,
                    'job_id' => self::JOB_ID,
                    'created_at' => '2026-09-28T10:00:00+00:00',
                    'status' => 'open',
                    'reason' => 'not_fixed',
                    'details' => 'The laptop still does not turn on after the repair.',
                    'photo_paths' => [self::JOB_ID.'/1.jpg'],
                    'raised_by_role' => 'client',
                    'raised_by_name' => 'Juan Dela Cruz',
                    'device_type' => 'laptop',
                    'problem_symptom' => 'laptop_wont_power_on',
                    'client_name' => 'Juan Dela Cruz',
                    'technician_name' => 'Ryan Santos',
                ]]);
            },
            self::BASE.'/rest/v1/identity_verifications*' => Http::response('', 200, ['Content-Range' => '0-0/0']),
            self::BASE.'/storage/v1/object/sign/dispute-photos/*' => Http::response([
                'signedURL' => '/object/sign/dispute-photos/'.self::JOB_ID.'/1.jpg?token=abc',
            ]),
        ]);
    }

    public function test_guests_are_sent_to_sign_in(): void
    {
        Http::preventStrayRequests();

        $this->get(route('disputes.index'))->assertRedirect(route('login'));
    }

    public function test_an_admin_sees_open_reports_with_their_photos_and_a_decision_form(): void
    {
        $this->fakeReadEndpoints();

        $this->withSession($this->signedIn())
            ->get(route('disputes.index'))
            ->assertOk()
            ->assertSee('The laptop still does not turn on after the repair.')
            ->assertSee('Reported by the client')
            ->assertSee(self::BASE.'/storage/v1/object/sign/dispute-photos/'.self::JOB_ID.'/1.jpg?token=abc', false)
            ->assertSee('Mark resolved');
    }

    public function test_a_decision_without_a_written_reason_is_refused(): void
    {
        Http::preventStrayRequests();

        $this->withSession($this->signedIn())
            ->post(route('disputes.update', self::DISPUTE_ID), ['decision' => 'resolved', 'note' => ''])
            ->assertSessionHasErrors([
                'note' => 'Write the decision out - both sides are shown it word for word.',
            ]);

        Http::assertNothingSent();
    }

    public function test_a_decision_is_recorded_by_the_signed_in_admin(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            self::BASE.'/rest/v1/rpc/resolve_job_dispute' => Http::response(['id' => self::DISPUTE_ID]),
        ]);

        $this->withSession($this->signedIn())
            ->post(route('disputes.update', self::DISPUTE_ID), [
                'decision' => 'resolved',
                'note' => '  The technician will return on Friday at no charge.  ',
            ])
            ->assertRedirect(route('disputes.index'))
            ->assertSessionHas('status', 'Resolved. Both people on the booking can now read your decision in the app.');

        Http::assertSent(fn (Request $request): bool => $request->url() === self::BASE.'/rest/v1/rpc/resolve_job_dispute'
            && $request['p_dispute_id'] === self::DISPUTE_ID
            && $request['p_decision'] === 'resolved'
            && $request['p_note'] === 'The technician will return on Friday at no charge.'
            && $request['p_admin_id'] === self::ADMIN_ID);
    }

    public function test_a_refusal_from_the_database_is_shown_to_the_admin(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            self::BASE.'/rest/v1/rpc/resolve_job_dispute' => Http::response(
                ['message' => 'That report was not found, or has already been decided.'],
                400,
            ),
        ]);

        $this->withSession($this->signedIn())
            ->from(route('disputes.index'))
            ->post(route('disputes.update', self::DISPUTE_ID), [
                'decision' => 'dismissed',
                'note' => 'Nothing to act on.',
            ])
            ->assertRedirect(route('disputes.index'))
            ->assertSessionHas('error', 'That report was not found, or has already been decided.');
    }

    public function test_a_malformed_report_id_is_not_found(): void
    {
        Http::preventStrayRequests();

        $this->withSession($this->signedIn())
            ->post('/disputes/not-a-uuid', ['decision' => 'resolved', 'note' => 'A valid note.'])
            ->assertNotFound();
    }
}
