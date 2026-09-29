# Community: the Q&A feed

The feature that replaced the Chat tab in both bottom bars. This is the
document to read before a defence: it covers what the feature does, the rules
that govern it, and why each rule is enforced where it is.

Companion documents:

- `docs/design-system.md` - the tokens and shared widgets the UI is built from
- `docs/rb-cars.md` - the matching engine, which this feature deliberately
  does not touch

---

## 1. The problem

A client with a broken laptop has two kinds of question, and before this
feature SUGO could only answer one of them.

1. **"Fix this thing."** A specific repair, on a specific device, that a
   specific technician is booked for. RB-CARS answers this.
2. **"What should I do?"** *Is this worth repairing? What specs should I buy?
   Is this noise normal?* There is no job here, no booking, and often no
   repair at the end of it - so there was nowhere in the app to ask.

The second kind is where a marketplace earns trust before it earns money. A
client who got a straight answer about whether their laptop was worth fixing
comes back when something actually breaks.

## 2. The shape, and why it is asymmetric

| Role | Ask | Answer | Rate |
|---|---|---|---|
| Client | yes | yes | yes |
| Technician | no | yes | no |

Three deliberate asymmetries:

**Clients ask; technicians do not.** The feed's value is that answers come
from verified, rated professionals. A technician posting questions would blur
what the feed is for, and there is no "+" button on their navigation bar as a
result.

**Clients rate; technicians do not.** Only the person with the problem can say
whether an answer solved it. Letting technicians rate each other turns
reputation into a popularity contest among competitors.

**Clients may answer their own thread.** This was allowed on purpose. A client
adding "sorry, it is the 2019 model" is normal and useful, and blocking it
would push that clarification into a second question. Their comments are not
votable and earn nothing - `author_role` is what separates the two cases.

## 3. Why thumbs up, not stars

The brief allowed either. The feed uses a single "Helpful" vote.

A five-star rating on an *answer* is ambiguous in a way it is not on a
completed repair. Three stars on "did this help?" is not something anyone can
act on, and it invites the rating inflation that makes marketplace star
averages cluster uselessly between 4.4 and 4.9.

"Was this helpful?" has one honest answer and one honest silence. It is one
tap, it makes *Most Helpful* a plain count, and it makes reputation a plain
multiple of that count.

**There is no downvote.** A technician's livelihood is attached to this
profile, and a brigading mechanism is not something a marketplace should ship.

## 4. Reputation, and the one thing it must never do

Five points per helpful vote, maintained entirely by database triggers.

### Why it lives in its own table

The obvious implementation is `alter table technicians add column
reputation_points`. The schema deliberately does not do that:

1. `technicians` is one of the four RB-CARS tables, and that schema is frozen.
   A community feature has no business widening it.

2. **It makes a design promise enforceable.** Community points must never
   influence who gets offered a job. Otherwise a technician can farm upvotes
   into paid work, and the matching score stops meaning what `docs/rb-cars.md`
   says it means.

Keeping the number in `community_reputation` - a table the matcher does not
read - makes that structural. The defensible answer to *"can a technician
farm upvotes to get more jobs?"* is **no, the matcher cannot see the number**,
which is a much stronger claim than "it does not currently read it".

### Why the app cannot write points

`CommunityService` has no method that writes reputation, and
`community_reputation` has **no insert, update or delete policy for anybody**.
The table is maintained exclusively by `SECURITY DEFINER` triggers. A points
economy the client can write to is not an economy.

### Why it recomputes rather than increments

`recalc_community_reputation` recounts from source on every change:

```sql
select count(*), coalesce(sum(c.helpful_count), 0)
from public.community_comments c
where c.author_id = p_technician and c.author_role = 'technician';
```

An increment is one missed trigger away from a total that never reconciles,
and a wrong reputation is worse than a slow one. The columns are indexed and a
technician has tens of answers, not millions.

## 5. The rules, and where each is enforced

Every rule is in the database, because a rule enforced only in Dart is a
suggestion.

| Rule | Enforced by |
|---|---|
| Only clients post questions | `community_posts_insert_client` policy |
| An answer's role cannot be forged | `author_role = public.profile_role(auth.uid())` in the insert policy |
| One vote per person per answer | primary key `(comment_id, voter_id)` |
| Only clients vote | `community_votes_insert_client` policy |
| Only technician answers are votable | `exists (... c.author_role = 'technician')` in the same policy |
| Nobody votes on their own answer | `c.author_id <> auth.uid()` in the same policy |
| An answer cannot be edited after it is rated | no update policy on `community_comments` |
| Points cannot be written by the app | no write policy on `community_reputation` |

### Why `author_role` is stored and not joined

It is frozen at insert from the author's profile. Read live from `profiles`
instead, a client who later registered as a technician would retroactively
turn every comment they had ever posted into a votable, points-earning answer.

### Why author details come from a function

`profiles` is readable only by its owner, so a plain join leaves every author's
name null - the same problem `job_conversations` hit in migration
20260907000013. `community_author()` is a `SECURITY DEFINER` hop returning
only what already appears publicly beside an answer: name, picture, role, tier,
badge, verification, rating and points.

**Phone, email and address are not in it and must not be added.**

## 6. What is on screen

| File | What it is |
|---|---|
| `community_feed_view.dart` | The tab. Sort, topic filter, list. One widget for both roles - the role changes two things, not the screen |
| `community_post_screen.dart` | A question and its answers, with the reply bar |
| `ask_question_sheet.dart` | The composer. A sheet, because an abandoned draft should be cheap |
| `community_post_card.dart` | A feed row |
| `community_answer_card.dart` | An answer and its Helpful control |
| `community_author_row.dart` | The byline: picture, name, tier, points |

### Two sort defaults, on purpose

The **feed** defaults to *Recent*, sorted on `last_activity_at` - a question
still being answered should not sink below a dead one.

A **thread** defaults to *Most Helpful*. Within a thread the reader wants the
best answer, not the newest one, and an accepted answer sinking below a late
"same problem here" is the failure mode every Q&A site is judged on.

### Voting is optimistic

The button flips locally, then sends. A vote that waits for a round trip
before responding feels broken on a slow connection; the server is the
authority either way, and a failure restores the previous state and says why.

A duplicate-key error is swallowed rather than surfaced - it means the vote was
already there, so the end state is the one the user asked for.

## 7. What happened to direct messaging

**Nothing was deleted.** Job chat, `job_messages` and `ChatService` are
untouched.

The Chat *tab* opened a cross-job inbox, which was the wrong home for it twice
over: a thread only exists once a job is booked, so the tab was empty for every
new client, and a conversation about a specific repair belongs on that repair.

- **A thread** is reached from Bookings → a job → "Open chat", as before.
- **The inbox** moved to the envelope in each dashboard header, where its
  unread badge now lives.

The badge changed from a dot to a count in the move. On the nav bar a count was
noise, because the tab was one tap away; in the header the inbox is off-screen,
so "how many am I missing?" is a question the badge can usefully answer.

## 8. The grant trap, and how it was caught

Worth being able to tell this story, because it is the kind of mistake that
looks like nothing and is the reason `SECURITY DEFINER` has a bad reputation.

Migration `20260921000001` ended each helper with:

```sql
grant execute on function public.profile_role(uuid) to authenticated;
```

That reads like a restriction. **It is not.** `create function` hands EXECUTE
to `PUBLIC` by default, and `GRANT` is additive - so the line widened nothing
and restricted nothing. Every helper stayed callable over PostgREST by the
`anon` role.

It was caught by probing the live project after the push, rather than by
reading the file:

```
POST /rest/v1/rpc/recalc_community_reputation   ->  409  23503 foreign key
```

A foreign-key violation means the function **executed**. An anonymous caller
had reached a `SECURITY DEFINER` function that writes to
`community_reputation` - the one table with no write policy for anybody,
precisely because points must not be writable by the app.

### What the exposure actually was

Small, but not nothing, and worth being precise about:

- `recalc_community_reputation` **could not forge a total.** It recomputes from
  source, so the only value it can write is the correct one, and the worst an
  attacker achieves is making the database agree with itself.
- `profile_role` and `community_author` return only what already appears
  publicly beside an answer. No phone, no email, no address. This disclosed
  nothing private - but it did let an anonymous caller enumerate display names
  and tiers by uuid.

Neither is a breach. Both are things that should simply not be reachable, and
*"you cannot reach the function that writes the points table"* is a far better
answer than *"you can reach it, and here is why it does not matter."*

### The fix

`20260921000002_community_function_grants.sql` revokes from `PUBLIC` **first**,
then grants to exactly the role that needs it. Order matters - granting before
revoking leaves `PUBLIC` in place.

The trigger internals (`recalc_community_reputation`, `sync_community_vote`,
`sync_community_comment`) are revoked from every client role. This costs the
feature nothing: PostgreSQL checks EXECUTE on a trigger function when the
trigger is **created**, not each time it fires, and `recalc_*` is reached only
from inside the `sync_*` functions, which are `SECURITY DEFINER` and execute as
the function owner.

Verified after the push:

```
BLOCKED  401  rpc recalc_community_reputation
BLOCKED  401  rpc profile_role
BLOCKED  401  rpc community_author
BLOCKED  404  rpc sync_community_vote
BLOCKED  401  select community_feed
BLOCKED  401  select community_reputation
```

### The general lesson

In PostgreSQL, a `grant` is never a restriction. If a function should not be
world-callable, the `revoke from public` has to be written explicitly - and on
Supabase that matters more than usual, because PostgREST turns every function
in `public` into an HTTP endpoint.

## 9. Applying the migration

```bash
supabase db push
```

Or apply `supabase/migrations/20260921000001_community.sql` directly.

It is self-contained and idempotent: every `create` is `if not exists`, every
policy is `drop policy if exists` first, and the realtime block is wrapped in
the same conditional shape as `job_messages` so a project without the
`supabase_realtime` publication still applies it.

### Verifying it works

```sql
-- A technician should not be able to post a question.
set local role authenticated;
insert into public.community_posts (author_id, title, body)
values (auth.uid(), 'Test question here', 'Body text for the test');
-- expected: new row violates row-level security policy

-- A client should not be able to vote on their own comment.
insert into public.community_votes (comment_id, voter_id)
values ('<a comment you wrote>', auth.uid());
-- expected: new row violates row-level security policy

-- Points should be a multiple of five.
select technician_id, points, helpful_votes from public.community_reputation;
-- expected: points = helpful_votes * 5, always
```
