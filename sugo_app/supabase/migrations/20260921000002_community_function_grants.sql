-- SUGO: lock down the Community helper functions
--
-- Follow-up to 20260921000001. That migration granted EXECUTE on its helpers
-- to `authenticated` and left it there, which is the trap PostgreSQL sets for
-- everybody at least once:
--
--   **GRANT is additive, and every function is already granted to PUBLIC.**
--
-- `create function` hands EXECUTE to PUBLIC by default, so adding a grant to
-- `authenticated` widened nothing and restricted nothing. The functions were
-- callable over PostgREST by the `anon` role - verified against the live
-- project, where `rpc/recalc_community_reputation` ran as an anonymous caller
-- and got as far as a foreign-key violation, which means it executed.
--
-- WHAT THE ACTUAL EXPOSURE WAS. Small, but not nothing:
--
--   * `recalc_community_reputation` is SECURITY DEFINER and WRITES to
--     `community_reputation` - the one table with no write policy for anybody,
--     precisely because points must not be writable by the app.
--
--     It could not be used to forge a total. It recomputes from source, so the
--     only value it can ever write is the correct one, and the worst an
--     attacker achieves is making the database agree with itself. But "you
--     cannot reach the function that writes the points table" is a far better
--     answer at a defence than "you can reach it, and here is why it does not
--     matter".
--
--   * `profile_role` and `community_author` are SECURITY DEFINER reads that
--     bypass the `profiles` RLS policy. They return only what already appears
--     publicly beside an answer - no phone, no email, no address - so this was
--     a disclosure of nothing private. Still, an anonymous caller enumerating
--     display names and tiers by uuid is not a thing to leave switched on.
--
-- The fix is REVOKE FROM PUBLIC first, then grant to exactly the role that
-- needs it. Order matters: granting before revoking leaves PUBLIC in place.

-- ---------------------------------------------------------------------------
-- 1. Functions the app calls, directly or through a view
-- ---------------------------------------------------------------------------
--
-- `community_feed` and `community_thread` are `security_invoker` views that
-- call these, so the *querying* user needs EXECUTE. That is `authenticated`
-- and nobody else - an anonymous visitor has no business reading the feed,
-- and every select policy on it is already `to authenticated`.

revoke all on function public.profile_role(uuid) from public;
revoke all on function public.profile_role(uuid) from anon;
grant execute on function public.profile_role(uuid) to authenticated;

revoke all on function public.community_author(uuid) from public;
revoke all on function public.community_author(uuid) from anon;
grant execute on function public.community_author(uuid) to authenticated;

-- The points rule. Harmless - it returns a constant - but the app hardcodes
-- the same 5 in `_PointsEarned`, so reading it back is a convenience for a
-- signed-in client and not something to expose more widely than that.
revoke all on function public.community_points_per_vote() from public;
revoke all on function public.community_points_per_vote() from anon;
grant execute on function public.community_points_per_vote() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Internals nobody may call
-- ---------------------------------------------------------------------------
--
-- These run from triggers, and a trigger does not consult the calling user's
-- EXECUTE privilege - PostgreSQL checks that when the trigger is CREATED, not
-- each time it fires. `recalc_community_reputation` is likewise reached only
-- from inside `sync_*`, which are SECURITY DEFINER and therefore execute as
-- the function owner.
--
-- So revoking from every client role costs the feature nothing and closes the
-- RPC surface completely.

revoke all on function public.recalc_community_reputation(uuid) from public;
revoke all on function public.recalc_community_reputation(uuid) from anon;
revoke all on function public.recalc_community_reputation(uuid) from authenticated;

revoke all on function public.sync_community_vote() from public;
revoke all on function public.sync_community_vote() from anon;
revoke all on function public.sync_community_vote() from authenticated;

revoke all on function public.sync_community_comment() from public;
revoke all on function public.sync_community_comment() from anon;
revoke all on function public.sync_community_comment() from authenticated;

-- ---------------------------------------------------------------------------
-- 3. The tables themselves
-- ---------------------------------------------------------------------------
--
-- RLS already refuses anon on every one of them - that was verified against
-- the live project, and an anonymous insert into `community_posts` comes back
-- 42501. This removes the table grants as well, so an anonymous request is
-- refused at the privilege check rather than by a policy.
--
-- Defence in depth, and it makes the intent legible in `\dp`: a reader can see
-- that anon was never meant to touch these, instead of inferring it from the
-- absence of a policy.

revoke all on table public.community_posts from anon;
revoke all on table public.community_comments from anon;
revoke all on table public.community_votes from anon;
revoke all on table public.community_reputation from anon;
revoke all on table public.community_feed from anon;
revoke all on table public.community_thread from anon;
