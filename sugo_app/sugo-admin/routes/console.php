<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

/*
 * Sends one real approval email, to check delivery end to end.
 *
 *   php artisan sugo:mail-test you@example.com
 *   php artisan sugo:mail-test you@example.com --role=technician
 *
 * Why this exists: approval emails had been "sent" since 7 September and not
 * one arrived, because MAIL_MAILER was `log` - Laravel wrote each message to
 * storage/logs/laravel.log and reported success. Nothing in the admin panel
 * could reveal that, since the approval itself works either way. This command
 * uses the real mailable and fails loudly, so a misconfigured mailer shows up
 * in ten seconds instead of in an applicant's empty inbox.
 */
Artisan::command('sugo:mail-test {email} {--role=client}', function (string $email) {
    $mailer = config('mail.default');

    if ($mailer === 'log' || $mailer === 'array') {
        $this->error("MAIL_MAILER is '{$mailer}': mail is written to the log, not sent.");
        $this->line('Set MAIL_MAILER=smtp and the SMTP settings in .env, then run:');
        $this->line('  php artisan config:clear');

        return 1;
    }

    // SMTP with no password fails at Gmail's AUTH step with a message about
    // "Username and Password not accepted", which reads like a wrong password
    // rather than a missing one. Say which it is.
    if ($mailer === 'smtp' && blank(config('mail.mailers.smtp.password'))) {
        $this->error('MAIL_PASSWORD is empty.');
        $this->line('Paste the Google App Password that Supabase > Auth > SMTP uses into');
        $this->line('sugo-admin/.env, then run: php artisan config:clear');

        return 1;
    }

    $role = $this->option('role') === 'technician' ? 'technician' : 'client';

    try {
        \Illuminate\Support\Facades\Mail::to($email)->send(
            new \App\Mail\AccountApproved(fullName: 'Test Applicant', role: $role),
        );
    } catch (\Throwable $e) {
        $this->error('Sending failed: '.$e->getMessage());

        return 1;
    }

    $this->info("Sent a {$role} approval email to {$email} via '{$mailer}'.");
    $this->line('Check the inbox, and the spam folder the first time.');

    return 0;
})->purpose('Send a real approval email to check mail delivery');
