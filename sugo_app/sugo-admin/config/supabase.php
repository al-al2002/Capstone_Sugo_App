<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Supabase project
    |--------------------------------------------------------------------------
    |
    | This panel has no database of its own. Admin sign-in goes to Supabase
    | Auth and every row it displays is fetched from Supabase over HTTP, so
    | there is exactly one account store and one source of truth for the whole
    | of SUGO.
    |
    */

    'url' => env('SUPABASE_URL'),

    /*
    | The anon key. Used only for the sign-in call, which is what an ordinary
    | client would make. It grants nothing on its own - every table is behind
    | RLS.
    */
    'anon_key' => env('SUPABASE_ANON_KEY'),

    /*
    | The service role key. This BYPASSES EVERY RLS POLICY.
    |
    | It is what lets a reviewer read another person's identity documents,
    | which no ordinary session may do - `identity_verifications` is restricted
    | to `user_id = auth.uid()`. That power is the whole reason the panel can
    | work, and the whole reason it must never leave the server: it is read in
    | PHP, sent in a server-to-server header, and never passed to a Blade view
    | or rendered into a page.
    */
    'service_role_key' => env('SUPABASE_SERVICE_ROLE_KEY'),

    /*
    |--------------------------------------------------------------------------
    | Storage
    |--------------------------------------------------------------------------
    |
    | Identity documents live in a private bucket. The panel mints a
    | short-lived signed URL for each image when a reviewer opens a submission.
    |
    | Ten minutes: long enough to study both photos and write a decision,
    | short enough that a URL left in browser history or a screen recording is
    | dead well before anyone could reuse it.
    */

    'identity_bucket' => 'identity-documents',

    'signed_url_ttl' => 600,

    /*
    |--------------------------------------------------------------------------
    | HTTP
    |--------------------------------------------------------------------------
    */

    'timeout' => 15,

];
