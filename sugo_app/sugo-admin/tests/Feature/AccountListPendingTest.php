<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Accounts awaiting review are listed in ID review, not in the Technicians
 * and Clients lists (2026-11-17, at the user's request).
 */
class AccountListPendingTest extends TestCase
{
    private const BASE = 'https://project.supabase.test';

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
        return ['admin' => ['id' => 'a1', 'name' => 'Ana Admin', 'email' => 'ana@sugo.app']];
    }

    public function test_the_list_asks_for_everyone_but_the_accounts_awaiting_review(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            self::BASE.'/rest/v1/admin_applicant_detail*' => Http::response([], 200),
            self::BASE.'/rest/v1/technicians*' => Http::response([], 200),
            self::BASE.'/rest/v1/*' => Http::response('', 200, ['Content-Range' => '0-2/3']),
        ]);

        $this->withSession($this->signedIn())
            ->get(route('accounts.index', ['role' => 'technician']))
            ->assertOk()
            ->assertSee('awaiting review')
            ->assertSee('Open ID review')
            ->assertDontSee('Awaiting review (');

        Http::assertSent(function (Request $request): bool {
            return str_contains($request->url(), '/rest/v1/admin_applicant_detail')
                && ($request->data()['registration_status'] ?? null) === 'neq.pending_review';
        });
    }

    public function test_an_old_awaiting_review_link_goes_to_id_review(): void
    {
        Http::preventStrayRequests();
        Http::fake();

        $this->withSession($this->signedIn())
            ->get(route('accounts.index', ['role' => 'client', 'status' => 'pending_review']))
            ->assertRedirect(route('verifications.index', ['role' => 'client']));

        Http::assertNothingSent();
    }
}
