<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * The front door.
 *
 * This was Laravel's stock example, asserting that `/` answers 200. It failed
 * from the day the console got a login, because the right answer for a
 * signed-out visitor is to be sent to sign in. Rewritten 2026-11-17 to check
 * that behaviour instead of a page nobody should see.
 */
class ExampleTest extends TestCase
{
    public function test_a_signed_out_visitor_is_sent_to_sign_in(): void
    {
        $this->get('/')->assertRedirect(route('login'));
    }

    public function test_the_sign_in_page_itself_is_open(): void
    {
        $this->get(route('login'))->assertOk();
    }
}
