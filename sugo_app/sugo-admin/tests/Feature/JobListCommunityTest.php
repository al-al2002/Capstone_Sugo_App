<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Technician Community posts are not jobs (2026-11-17, at the user's
 * request): the Jobs page lists and counts bookings only. A community post
 * appears once the client books a technician for it - its service path then
 * changes to home_service or pickup, and the filter lets it through.
 */
class JobListCommunityTest extends TestCase
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

    public function test_the_jobs_page_asks_for_bookings_only(): void
    {
        Http::preventStrayRequests();
        Http::fake([
            self::BASE.'/rest/v1/admin_jobs*' => Http::response([], 200),
            self::BASE.'/rest/v1/*' => Http::response('', 200, ['Content-Range' => '0-0/1']),
        ]);

        $this->withSession(['admin' => ['id' => 'a1', 'name' => 'Ana Admin', 'email' => 'ana@sugo.app']])
            ->get(route('jobs.index', ['status' => 'all']))
            ->assertOk()
            ->assertSee('Technician Community questions are not listed');

        // The list...
        Http::assertSent(fn (Request $r): bool => str_contains($r->url(), '/rest/v1/admin_jobs')
            && ($r->data()['service_path'] ?? null) === 'neq.it_community');

        // ...and every count on the page.
        $jobCounts = collect(Http::recorded())
            ->map(fn (array $pair) => $pair[0])
            ->filter(fn (Request $r): bool => str_contains($r->url(), '/rest/v1/jobs'));

        $this->assertCount(3, $jobCounts);
        foreach ($jobCounts as $request) {
            $this->assertSame('neq.it_community', $request->data()['service_path'] ?? null);
        }
    }
}
