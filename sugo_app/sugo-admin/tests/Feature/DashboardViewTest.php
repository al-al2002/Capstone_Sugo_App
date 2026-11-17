<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The renovated dashboard and console shell (2026-11-17).
 *
 * Renders the dashboard view directly with fixed figures, so it checks the
 * markup without the controller's six Supabase reads. Supabase is faked only
 * for the two counts the layout's badges (and now the hero) ask for.
 */
class DashboardViewTest extends TestCase
{
    private const BASE = 'https://project.supabase.test';

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'supabase.url' => self::BASE,
            'supabase.service_role_key' => 'test-service-key',
        ]);

        Http::preventStrayRequests();
        Http::fake([
            // 3 open disputes, 2 people waiting on review.
            self::BASE.'/rest/v1/admin_disputes*' => Http::response('', 200, ['Content-Range' => '0-2/3']),
            self::BASE.'/rest/v1/identity_verifications*' => Http::response('', 200, ['Content-Range' => '0-1/2']),
        ]);

        session(['admin' => ['id' => 'a1', 'name' => 'Ana Reyes', 'email' => 'ana@sugo.app']]);
    }

    /** @return array<string, mixed> */
    private function figures(int $pending = 2): array
    {
        $daily = [];
        for ($i = 13; $i >= 0; $i--) {
            $daily[] = ['day' => now()->subDays($i)->toDateString(), 'posted' => $i % 4, 'completed' => $i % 3];
        }

        return [
            'stats' => ['pending_verifications' => $pending, 'active_accounts' => 40],
            'queue' => [],
            'recent' => [],
            'liveJobs' => [],
            'analytics' => [
                'users' => ['clients' => 30, 'technicians' => 12, 'new_7d' => 5],
                'jobs' => [
                    'total' => 1234, 'last_7d' => 9, 'completion_rate' => 87.5,
                    'matched' => 2, 'confirmed' => 1, 'in_progress' => 1, 'completed' => 20,
                ],
                'ratings' => ['technician_avg' => 4.62, 'technician_count' => 18],
                'community' => [],
                'daily' => $daily,
                'devices' => [['device_type' => 'laptop', 'jobs' => 7]],
                'top_technicians' => [
                    ['name' => 'Ryan Santos', 'jobs' => 9, 'reviews' => 7, 'rating' => 4.9],
                ],
                'top_clients' => [],
            ],
        ];
    }

    public function test_the_hero_greets_the_admin_and_says_what_needs_doing(): void
    {
        $html = view('dashboard', $this->figures())->render();

        $this->assertMatchesRegularExpression('/Good (morning|afternoon|evening), Ana/', $html);
        $this->assertStringContainsString('2 people waiting to be verified.', $html);
        $this->assertStringContainsString('4 jobs live right now.', $html);
        $this->assertStringContainsString('Open the queue', $html);
    }

    public function test_the_open_dispute_count_reaches_the_dashboard_itself(): void
    {
        // A child view renders before its layout, so this only works because
        // the composer is attached to `dashboard` as well as the layout.
        $html = view('dashboard', $this->figures())->render();

        $this->assertMatchesRegularExpression(
            '/data-count-to="3">3<\/div>\s*<div[^>]*>Open disputes/',
            $html,
        );
        // Two views asked; once() kept it to one count per table.
        Http::assertSentCount(2);
    }

    public function test_figures_count_up_from_the_values_already_printed(): void
    {
        $html = view('dashboard', $this->figures())->render();

        // Printed for anyone without JavaScript; counted up for everyone else.
        $this->assertStringContainsString('data-count-to="1234"', $html);
        $this->assertStringContainsString('1,234', $html);
        $this->assertStringContainsString('data-count-to="87.5"', $html);
        $this->assertStringContainsString('data-suffix="%"', $html);
        $this->assertStringContainsString('<polyline points=', $html); // the sparkline
    }

    public function test_a_clear_queue_says_so_and_offers_no_queue_button(): void
    {
        $html = view('dashboard', $this->figures(pending: 0))->render();

        $this->assertStringContainsString('The review queue is clear.', $html);
        $this->assertStringNotContainsString('Open the queue', $html);
    }

    public function test_the_layout_carries_the_motion_kit_and_the_navy_shell(): void
    {
        $html = view('dashboard', $this->figures())->render();

        $this->assertStringContainsString('class="sugo-page"', $html);
        $this->assertStringContainsString('@keyframes sugo-rise', $html);
        $this->assertStringContainsString('prefers-reduced-motion', $html);
        $this->assertStringContainsString('from-navy', $html);
    }
}
