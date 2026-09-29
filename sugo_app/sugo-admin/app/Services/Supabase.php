<?php

namespace App\Services;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * The one place this panel talks to Supabase.
 *
 * Everything goes over HTTP - PostgREST for tables and views, `/rpc/` for the
 * review functions, `/auth/v1/` for sign-in, `/storage/v1/` for signed URLs.
 * There is deliberately no direct Postgres connection: it would need the
 * database password and the `pdo_pgsql` extension, and it would bypass the
 * RPC functions that hold the review rules.
 *
 * ## The security seam
 *
 * Two keys, used for two different things:
 *
 *  - **anon** signs the admin in. That call is exactly what any client would
 *    make, and it proves the password. It grants nothing by itself.
 *  - **service_role** reads and writes as the system. It bypasses every RLS
 *    policy, which is the only way a reviewer can see someone else's identity
 *    document - `identity_verifications` is restricted to `user_id =
 *    auth.uid()` for everybody else.
 *
 * The pattern used everywhere in this app, matching the edge functions:
 * establish who is asking (the session, set at login and re-checked by
 * `EnsureAdmin`), *then* act with elevated privilege. Never elevated privilege
 * on an unauthenticated request.
 */
class Supabase
{
    public function __construct(
        private readonly ?string $url = null,
        private readonly ?string $anonKey = null,
        private readonly ?string $serviceKey = null,
    ) {}

    private function baseUrl(): string
    {
        $url = $this->url ?? config('supabase.url');

        if (blank($url)) {
            throw new RuntimeException(
                'SUPABASE_URL is not set. Copy the value from your Supabase '.
                'project settings into sugo-admin/.env.'
            );
        }

        return rtrim($url, '/');
    }

    private function anon(): string
    {
        return $this->anonKey ?? (string) config('supabase.anon_key');
    }

    private function service(): string
    {
        $key = $this->serviceKey ?? (string) config('supabase.service_role_key');

        if (blank($key)) {
            throw new RuntimeException(
                'SUPABASE_SERVICE_ROLE_KEY is not set. The panel cannot read '.
                'submissions without it - see docs/admin-panel.md.'
            );
        }

        return $key;
    }

    /** A request signed as the system. Bypasses RLS. */
    private function asService(): PendingRequest
    {
        return Http::withHeaders([
            'apikey' => $this->service(),
            'Authorization' => 'Bearer '.$this->service(),
            'Content-Type' => 'application/json',
        ])->timeout((int) config('supabase.timeout', 15));
    }

    // -----------------------------------------------------------------  auth

    /**
     * Signs an administrator in.
     *
     * Two checks, and both are required:
     *
     *  1. Supabase Auth accepts the password. That proves the credential.
     *  2. The matching `profiles` row has `role = 'admin'`. That proves
     *     authorisation.
     *
     * A technician's or client's own login would pass step 1 perfectly well -
     * they are valid accounts on the same Auth instance. Step 2 is what keeps
     * them out of the review console, and it is checked here rather than in
     * the controller so no future sign-in path can forget it.
     *
     * @return array{id:string,email:string,name:?string}|null
     */
    public function signInAdmin(string $email, string $password): ?array
    {
        $response = Http::withHeaders([
            'apikey' => $this->anon(),
            'Content-Type' => 'application/json',
        ])
            ->timeout((int) config('supabase.timeout', 15))
            ->post($this->baseUrl().'/auth/v1/token?grant_type=password', [
                'email' => $email,
                'password' => $password,
            ]);

        if (! $response->successful()) {
            // Logged, not shown. The caller reports one generic message for
            // every failure so the form cannot be used to discover which
            // addresses have accounts.
            Log::info('Supabase sign-in refused', [
                'email' => $email,
                'status' => $response->status(),
            ]);

            return null;
        }

        $userId = $response->json('user.id');

        if (! is_string($userId)) {
            return null;
        }

        $profile = $this->first('profiles', [
            'id' => 'eq.'.$userId,
            'select' => 'id,full_name,role',
        ]);

        if (($profile['role'] ?? null) !== 'admin') {
            Log::warning('Non-admin attempted to sign in to the review console', [
                'user_id' => $userId,
                'role' => $profile['role'] ?? null,
            ]);

            return null;
        }

        return [
            'id' => $userId,
            'email' => (string) $response->json('user.email'),
            'name' => $profile['full_name'] ?? null,
        ];
    }

    // ----------------------------------------------------------------  reads

    /**
     * Selects rows from a table or view.
     *
     * @param  array<string,string>  $query  PostgREST filters, e.g.
     *                                       ['status' => 'eq.pending']
     * @return array<int,array<string,mixed>>
     */
    public function select(string $table, array $query = []): array
    {
        $response = $this->asService()->get($this->baseUrl().'/rest/v1/'.$table, $query);

        if (! $response->successful()) {
            Log::error('Supabase select failed', [
                'table' => $table,
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            throw new RuntimeException(
                'Could not read '.$table.' from Supabase ('.$response->status().').'
            );
        }

        return $response->json() ?? [];
    }

    /**
     * The first matching row, or null.
     *
     * @param  array<string,string>  $query
     * @return array<string,mixed>|null
     */
    public function first(string $table, array $query = []): ?array
    {
        $rows = $this->select($table, $query + ['limit' => '1']);

        return $rows[0] ?? null;
    }

    /**
     * Counts rows without transferring them.
     *
     * Uses PostgREST's `Prefer: count=exact` with an empty range, so the
     * server answers with a Content-Range header and no body.
     *
     * @param  array<string,string>  $query
     */
    public function count(string $table, array $query = []): int
    {
        $response = $this->asService()
            ->withHeaders(['Prefer' => 'count=exact', 'Range' => '0-0'])
            ->get($this->baseUrl().'/rest/v1/'.$table, $query + ['select' => 'id']);

        $range = $response->header('Content-Range');

        // Format is "0-0/123"; the part after the slash is the total.
        if (is_string($range) && str_contains($range, '/')) {
            return (int) explode('/', $range)[1];
        }

        return 0;
    }

    // ------------------------------------------------------------------  rpc

    /**
     * Calls a Postgres function.
     *
     * Every state change this panel makes goes through one of these rather
     * than a direct table write. That is not ceremony: the rules that decide
     * what a decision *means* - a rejection needs a reason, an approval only
     * activates when the rest of registration is finished, a technician's
     * `is_verified` may only be set when both hold - live inside those
     * functions. A direct `PATCH` on the table would skip all of it.
     *
     * @param  array<string,mixed>  $params
     */
    public function rpc(string $function, array $params = []): mixed
    {
        $response = $this->asService()
            ->post($this->baseUrl().'/rest/v1/rpc/'.$function, $params);

        if (! $response->successful()) {
            Log::error('Supabase RPC failed', [
                'function' => $function,
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            // The SQL functions raise exceptions whose messages are written for
            // a human ("A rejection must include a reason for the applicant"),
            // so the message is surfaced rather than swallowed.
            $message = $response->json('message') ?? 'The request was refused.';

            throw new RuntimeException($message);
        }

        return $response->json();
    }

    // --------------------------------------------------------------  storage

    /**
     * A short-lived URL for a private object.
     *
     * Identity documents live in a private bucket precisely so they are not
     * reachable from a guessable link. A reviewer needs to see them, so the
     * panel mints a signed URL that expires in minutes.
     *
     * Returns null rather than throwing: one unreadable image should render as
     * a placeholder next to the other, not blank the whole review screen.
     */
    public function signedUrl(?string $objectPath, ?int $ttl = null, ?string $bucket = null): ?string
    {
        if (blank($objectPath)) {
            return null;
        }

        // The identity bucket unless told otherwise - dispute photos live in
        // their own private `dispute-photos` bucket.
        $bucket ??= (string) config('supabase.identity_bucket');
        $ttl ??= (int) config('supabase.signed_url_ttl', 600);

        $response = $this->asService()->post(
            $this->baseUrl().'/storage/v1/object/sign/'.$bucket.'/'.ltrim($objectPath, '/'),
            ['expiresIn' => $ttl],
        );

        if (! $response->successful()) {
            Log::warning('Could not sign storage object', [
                'path' => $objectPath,
                'status' => $response->status(),
            ]);

            return null;
        }

        $signed = $response->json('signedURL') ?? $response->json('signedUrl');

        if (! is_string($signed)) {
            return null;
        }

        return $this->baseUrl().'/storage/v1'.(str_starts_with($signed, '/') ? '' : '/').$signed;
    }

    /**
     * A public URL, for objects in the public `job-photos` bucket.
     *
     * Portfolio images are promotional and are stored publicly, so they need
     * no signing. The column already holds a full URL in that case; this only
     * handles a bare path.
     */
    public function publicUrl(string $bucket, string $objectPath): string
    {
        if (str_starts_with($objectPath, 'http')) {
            return $objectPath;
        }

        return $this->baseUrl().'/storage/v1/object/public/'.$bucket.'/'.ltrim($objectPath, '/');
    }
}
