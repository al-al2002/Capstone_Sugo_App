-- SUGO: repair NULL token columns on hand-created auth users
--
-- ## The symptom
--
-- Signing in as admin@sugo.ph returned:
--
--   HTTP 500 {"error_code":"unexpected_failure",
--             "msg":"Database error querying schema"}
--
-- The account existed, the password hash was correct, the email was confirmed,
-- and the `auth.identities` row was present. The sign-in still failed.
--
-- ## The cause
--
-- `auth.users` has eight token columns that Postgres marks NULLABLE:
--
--   confirmation_token          recovery_token
--   email_change                email_change_token_new
--   email_change_token_current  phone_change
--   phone_change_token          reauthentication_token
--
-- GoTrue scans them into plain Go `string` fields, which cannot hold NULL. A
-- row created by the Auth admin API always writes '' into them, so the problem
-- never appears for a normally-registered user - but an INSERT written by hand
-- leaves them NULL, and every sign-in for that account then fails inside
-- GoTrue's row scan. The 500 names neither the column nor the row, which is
-- what makes it hard to place.
--
-- ## The fix
--
-- Normalise them to ''. 20260907000006 now writes them correctly on a fresh
-- database; this migration repairs any account created before that, and is
-- harmless when there is nothing to repair.
--
-- Scoped to accounts that have no password of their own OR are otherwise
-- already broken, rather than rewriting every row: this touches the auth
-- schema, which is Supabase's, so it changes as little as it can.

update auth.users
set confirmation_token         = coalesce(confirmation_token, ''),
    recovery_token             = coalesce(recovery_token, ''),
    email_change               = coalesce(email_change, ''),
    email_change_token_new     = coalesce(email_change_token_new, ''),
    email_change_token_current = coalesce(email_change_token_current, ''),
    phone_change               = coalesce(phone_change, ''),
    phone_change_token         = coalesce(phone_change_token, ''),
    reauthentication_token     = coalesce(reauthentication_token, '')
where confirmation_token is null
   or recovery_token is null
   or email_change is null
   or email_change_token_new is null
   or email_change_token_current is null
   or phone_change is null
   or phone_change_token is null
   or reauthentication_token is null;
