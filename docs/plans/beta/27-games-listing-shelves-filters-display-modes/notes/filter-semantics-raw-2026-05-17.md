# /games filter semantics — raw input (2026-05-17)

> Source material for the Wave F RSpec coverage + backfill spec. Master agent
> (Claude) captured the user's verbatim explanation + clarifying Q&A in this
> file so the future spec-writing agent has the full context, not just the
> distilled rules in `docs/decisions/0013-games-filter-semantics.md` and the
> summary in `docs/design.md ### Filter semantics`.

---

## User's framing (verbatim)

> I think I need to clarify how the filters are working or should work. Think of
> the filters like this:
>
> 1. I wanna see games that are released or scheduled, owned or wishlisted on
>    Switch and PS5.
> 2. I wanna see games that I wishlisted on Steam.
> 3. I wanna see games that I played on PS5.
> 4. I wanna see games that will be released on Switch.
> 5. I wanna see games that are released and I wishlisted on PS5.

## User's stated rules (verbatim, a–i)

Verbatim user text, preserved as a fenced block so the per-rule line breaks
survive any markdown reformatter:

```text
So some of the filters have to influence others.

a. [x] played -> means [x] released [x] owned ; something can't be played
   unless owned and released
b. [x] owned -> means [x] released ; something can't be owned if not
   released
c. [x] wishlist are games that are now [x] owned so the opposite of owned;
   we can't have [x] wishlist and [x] played
d. [x] scheduled and [x] owned can be happening as I can preorder but
   [x] scheduled [x] owned [x] played can't be happened since [x] played
   is bound to [x] released
e. [x] released and [x] scheduled complement each other
f. [x] owned and [x] wishlist is basically just [x] owned and its negation.
g. [x] played and [x] PS5 means games that I played on [x] PS5, not games
   that are available on [x] PS5 or that I own on [x] PS5.
h. [x] owned and [x] PS5 means games that I own on [x] PS5
i. [x] released or [x] scheduled [x] wishlist [x] PS5 -> means games that
   are released or scheduled, that I don't own and that they are / will be
   available on PS5.

Catch all these and revisit the filters. These are very important. If
unclear, ask questions.
```

Note: the user wrote the rules with backticks around `[x] played` etc. Inside a
fenced `text` block the backticks would render literally as part of the content,
so they're dropped here for readability. The substance (rule logic) is
byte-equivalent.

## Claude master agent's clarifying questions (3) + user answers

### Q1 — Per-platform `played` data tracking

> Per rule (g) `played + PS5 = played ON PS5`. Current data: `Game.played_at` is
> a SINGLE timestamp — there's no per-platform played history. How to interpret
> `played + <platform>`?

Options offered:

- Add per-platform played tracking now (Recommended)
- Interpret as 'played + game-has-platform' (no per-platform)
- Defer the per-platform played until later — keep current global

**User answer:** "I will play a game on a single platform so record played time
but also which platform. I won't be playing same game on more than one platform,
but I can own a game on multiple platforms. Clear?"

**Master interpretation:** ONE-to-ONE mapping. Add a single `played_platform_id`
column on `games` table (FK to `platforms`, nullable). Existing `played_at`
stays as the global timestamp; the platform is recorded alongside it. No
separate join table needed because the user plays each game on exactly one
platform.

### Q2 — Cascade UI enforcement style

> Rules (a/b/c) describe IMPLIES + MUTEX relationships. How should the UI
> enforce them when you check chips?

Options offered:

- Check-only cascade + auto-uncheck mutex chips (Recommended)
- Check-only cascade (current spec 06 — implies only, no mutex)
- No cascade or mutex — user can check anything, backend returns empty for
  invalid combos

**User answer:** "You have to account for your example that I can check owned,
played, then if I check wishlist while owned is still checked, played doesn't
uncheck as it's a perfect valid situation, if I uncheck owned and I'm left with
wishlist and played then played should be unchecked. Clear?"

**Master interpretation:** BIDIRECTIONAL CONDITIONAL cascade. The mutex between
wishlist and played is NOT absolute — it's CONDITIONAL on `owned` being checked.
The actual rule is:

- played's hard dependency = `released + owned` (both must be checked)
- when ANY dependency becomes unchecked, played auto-unchecks
- wishlist + played CAN coexist IF owned is also checked (owned still satisfies
  played's dependency)

Worked example (user-provided):

1. Start: nothing checked.
2. Check `played` → cascade auto-checks `released + owned` + at least one
   platform (per existing spec 06).
3. Then check `wishlist` → `played` STAYS checked (owned still checked; played's
   dependency still met).
4. Then UNCHECK `owned` → `played` auto-unchecks (only `wishlist` left for
   ownership; played's dependency no longer met).

### Q3 — Recorded chip future

> Does `recorded` still exist as a filter chip on /games (was added as DISPLAY
> chip on /games/:id ownership section)?

Options offered:

- Not a filter chip — display-only on /games/:id
- Yes, add it as a filter chip too
- Skip for now, add later

**User answer:** "We'll visit that when we go to detail page and we might drop
recorded as it's implied by being played. Actually you can take this as a final
word: drop recorded as played and recorded is the same thing."

**Master interpretation:** DROP `recorded` entirely. Remove:

- `Games::RecordedChipComponent` (+ template)
- The "recorded" row from the /games/:id ownership section (was added in Wave
  C4)
- Any recorded-related filter token (was never a filter chip — just a display
  chip on the detail page)
- Keep `Game.recorded` SCOPE (if used by backend / videos / MCP) — only drop the
  UI surface

### Follow-up URL example (after Q&A)

> https://app.pitomd.com/games?filters=released,scheduled,owned,wishlist,switch2
> — as an example this has to produce results, since I didn't fill any played
> info for any game. We'll cover this later.
>
> Our class for Filter or if we don't have we should have a service / class,
> something, has to cover and take all these into accounts.

**Master interpretation:** the URL above (no `played` chip) MUST return non-zero
results. Per the rules:

- `released + scheduled` = lifecycle OR — every game (no exclusion)
- `owned + wishlist` = ownership OR per rule (f) — covers every game (owned ∪
  wishlist = all)
- `switch2` = platform filter — matches games with Switch or Switch 2
  availability
- No `played` checked = engagement axis inactive (no played filter)

Expected results: 5 games (Pragmata, Mandragora, Cyberpunk 2077, Terminator 2D,
Ghosts'n Goblins Resurrection) per the TOKEN_TO_PLATFORM_SLUGS fix that landed
earlier in the session.

The user is right that the existing `Games::Filter` class already exists; the
rewrite is in-place, not a new class.

---

## Implementation contract (cross-reference)

For the SHIPPED rules + ADR see:

- `docs/decisions/0013-games-filter-semantics.md` — ADR with formalized rules
- `docs/design.md ### Filter semantics` — short summary
- Master agent memory:
  `/home/catalin/.claude/projects/-home-catalin-Dev-pito/memory/project_games_filter_semantics.md`
- This file — RAW user input + Q&A verbatim

For Wave F spec writing, READ THIS FILE FIRST. The raw text contains nuances
(e.g., the conditional mutex worked example) that the distilled rules can lose
in summarization.

## Edge cases the spec MUST cover (master-flagged)

Beyond the user's 5 explicit examples + 9 rules, the spec writer should derive
RSpec coverage for:

1. All 5 of the user's example URLs (cases 1–5).
2. The follow-up URL `?filters=released,scheduled,owned,wishlist,switch2`
   (returns 5 games on Switch).
3. The conditional cascade walkthrough (4 steps in Q2 answer).
4. The `owned + wishlist + played` valid case (owned satisfies played).
5. The `wishlist + played` (no owned) invalid case → played auto-unchecks.
6. Per-platform `played + PS5` — depends on `played_platform_id` matching PS5
   platform record.
7. `wishlist` is GLOBAL (not per-platform): `wishlist + PS5` = doesn't own
   ANYWHERE AND has PS5 in availability. NOT "not owned on PS5".
8. `released + scheduled` both checked = lifecycle axis inactive (every game
   passes lifecycle).
9. `owned + wishlist` both checked = ownership axis inactive (per rule f, owned
   ∪ wishlist = all).
10. Platform token expansion: `switch2` matches DB slugs `switch` AND
    `switch-2`; `steam` matches `win + linux + mac + dos + web + steam`.
11. Empty platform set (no platform chip checked) = no platform filter.
12. Empty everything = `Game.none` (defensive — but user explicitly avoids this
    state via the cascade).
