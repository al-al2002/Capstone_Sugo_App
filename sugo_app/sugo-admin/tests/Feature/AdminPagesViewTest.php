<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The renovated console pages (2026-11-17), rendered with fixed data.
 *
 * Each page is rendered straight from its view, so these check the markup
 * end to end - the summary strip, the empty states, the motion kit - without
 * the controllers' Supabase reads. Only the layout's two badge counts are
 * faked.
 */
class AdminPagesViewTest extends TestCase
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
            self::BASE.'/rest/v1/admin_disputes*' => Http::response('', 200, ['Content-Range' => '0-0/0']),
            self::BASE.'/rest/v1/identity_verifications*' => Http::response('', 200, ['Content-Range' => '0-2/3']),
        ]);

        session(['admin' => ['id' => 'a1', 'name' => 'Ana Reyes', 'email' => 'ana@sugo.app']]);
    }

    public function test_the_jobs_list_opens_on_its_summary_and_handles_no_rows(): void
    {
        $html = view('jobs.index', [
            'filter' => 'active',
            'search' => '',
            'counts' => ['active' => 4, 'completed' => 7, 'cancelled' => 1, 'all' => 12],
            'jobs' => [],
        ])->render();

        $this->assertStringContainsString('data-count-to="12"', $html);
        $this->assertStringContainsString('jobs on SUGO', $html);
        $this->assertStringContainsString('4 active · 7 completed · 1 cancelled', $html);
        $this->assertStringContainsString('No jobs here', $html);
    }

    public function test_a_waiting_id_queue_turns_the_summary_amber(): void
    {
        $html = view('verifications.index', [
            'status' => 'pending',
            'role' => 'all',
            'counts' => ['pending' => 3, 'approved' => 10, 'rejected' => 2],
            'roleCounts' => ['all' => 3, 'technician' => 2, 'client' => 1],
            'rows' => [],
        ])->render();

        $this->assertStringContainsString('submissions waiting', $html);
        $this->assertStringContainsString('from-[#7C2D12]', $html); // the amber band
        $this->assertStringContainsString('Nobody can book or accept work', $html);
    }

    public function test_a_clear_dispute_queue_says_so(): void
    {
        $html = view('disputes.index', [
            'filter' => 'open',
            'counts' => ['open' => 0, 'decided' => 5, 'all' => 5],
            'disputes' => [],
        ])->render();

        $this->assertStringContainsString('open reports', $html);
        $this->assertStringContainsString('5 decided so far.', $html);
        $this->assertStringContainsString('No reports here', $html);
    }

    public function test_the_accounts_list_counts_its_people(): void
    {
        $html = view('accounts.index', [
            'role' => 'technician',
            'status' => 'all',
            'counts' => ['all' => 9, 'pending_review' => 2, 'active' => 6, 'incomplete' => 1, 'rejected' => 0],
            'rows' => [],
        ])->render();

        $this->assertStringContainsString('data-count-to="9"', $html);
        $this->assertStringContainsString('6 active · 1 incomplete · 0 rejected', $html);
        $this->assertStringContainsString('No accounts', $html);
        // Pending accounts are in ID review, with a way there - not a tab.
        $this->assertStringNotContainsString('Awaiting review (', $html);
        $this->assertStringContainsString('2 technicians awaiting review', $html);
        $this->assertStringContainsString('Open ID review', $html);
        $this->assertStringContainsString(route('verifications.index', ['role' => 'technician']), $html);
    }

    public function test_no_pending_accounts_means_no_id_review_notice(): void
    {
        $html = view('accounts.index', [
            'role' => 'client',
            'status' => 'all',
            'counts' => ['all' => 4, 'pending_review' => 0, 'active' => 4, 'incomplete' => 0, 'rejected' => 0],
            'rows' => [],
        ])->render();

        $this->assertStringNotContainsString('Open ID review', $html);
    }

    /**
     * The work each technician takes (2026-11-17): Home Service, Shop Repair
     * or both, as lit pills in the list.
     */
    public function test_the_technician_list_shows_the_work_each_one_takes(): void
    {
        $row = fn (string $id, string $name): array => [
            'user_id' => $id, 'full_name' => $name, 'email' => $id.'@sugo.app',
            'registration_status' => 'active', 'verified_specializations' => 1,
            'specialization_count' => 1, 'verification_tier' => 'basic',
            'technician_verified' => true, 'created_at' => '2026-11-17T08:00:00Z',
        ];

        $html = view('accounts.index', [
            'role' => 'technician',
            'status' => 'all',
            'counts' => ['all' => 3, 'pending_review' => 0, 'active' => 3, 'incomplete' => 0, 'rejected' => 0],
            'rows' => [$row('t1', 'Ryan'), $row('t2', 'Mae'), $row('t3', 'Jo')],
            'workTypes' => [
                't1' => ['offers_home_service' => true, 'offers_shop_repair' => true],
                't2' => ['offers_home_service' => true, 'offers_shop_repair' => false],
                't3' => ['offers_home_service' => false, 'offers_shop_repair' => true],
            ],
        ])->render();

        $this->assertStringContainsString('>Work</th>', $html);
        $this->assertStringContainsString('title="Home Service and Shop Repair"', $html);
        $this->assertStringContainsString('title="Home Service"', $html);
        $this->assertStringContainsString('title="Shop Repair"', $html);
        // A kind they do not take is shown struck through, not hidden.
        $this->assertStringContainsString('line-through', $html);
    }

    public function test_a_technician_account_shows_work_type_and_shop(): void
    {
        $account = [
            'user_id' => 't3', 'full_name' => 'Jo Santos', 'email' => 'jo@sugo.app',
            'registration_status' => 'active', 'phone' => null,
            'created_at' => '2026-11-17T08:00:00Z', 'registration_step' => null,
            'technician_verified' => true, 'verification_tier' => 'basic',
            'service_radius_km' => 10,
        ];
        $render = fn (array $work): string => view('accounts.show', [
            'account' => $account,
            'role' => 'technician',
            'verifications' => [],
            'specializations' => [],
            'documents' => [],
            'addresses' => [],
            'work' => $work,
        ])->render();

        $html = $render([
            'offers_home_service' => false, 'offers_shop_repair' => true,
            'shop_name' => 'Santos Repair Hub', 'shop_latitude' => 7.07, 'shop_longitude' => 125.61,
        ]);
        $this->assertStringContainsString('Work type', $html);
        $this->assertStringContainsString('title="Shop Repair"', $html);
        $this->assertStringContainsString('Santos Repair Hub', $html);

        // Shop Repair with no pin is flagged.
        $html = $render(['offers_home_service' => true, 'offers_shop_repair' => true]);
        $this->assertStringContainsString('title="Home Service and Shop Repair"', $html);
        $this->assertStringContainsString('Not pinned', $html);
    }

    public function test_the_work_type_label_reads_the_two_flags(): void
    {
        $this->assertSame('Home Service and Shop Repair', \App\Support\WorkType::label(['offers_home_service' => true, 'offers_shop_repair' => true]));
        $this->assertSame('Home Service', \App\Support\WorkType::label(['offers_home_service' => true, 'offers_shop_repair' => false]));
        $this->assertSame('Shop Repair', \App\Support\WorkType::label(['offers_home_service' => false, 'offers_shop_repair' => true]));
        // Missing flags read as the database default.
        $this->assertSame('Home Service and Shop Repair', \App\Support\WorkType::label([]));
        $this->assertSame('Not set', \App\Support\WorkType::label(null));
    }

    public function test_the_login_draws_the_road_and_carries_the_motion_kit(): void
    {
        session()->forget('admin');

        // Through the route, not view(): the form's @error needs the $errors
        // bag that only the web middleware shares.
        $html = $this->get(route('login'))->assertOk()->getContent();

        $this->assertStringContainsString('Every account is checked by a person.', $html);
        $this->assertStringContainsString('class="sugo-draw"', $html);
        $this->assertStringContainsString('@keyframes sugo-draw', $html);
        $this->assertStringContainsString('prefers-reduced-motion', $html);
        $this->assertStringContainsString('Every decision recorded with who made it', $html);
    }
}
