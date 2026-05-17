# ADR 0013 — /games filter semantics

## Status

Accepted, 2026-05-17. [skipci]

## Context

The `/games` filter chips (`released`, `scheduled`, `owned`, `wishlist`,
`played`, plus platform chips `ps5` / `switch2` / `steam`) had implementation
drift: chips were treated as flat AND constraints, leading to invalid combos
returning empty result sets. The most visible symptom — the URL
`?filters=released,scheduled,owned,wishlist,switch2` (no `played`) returned zero
games instead of the expected five Switch-family games (Pragmata, Mandragora,
Cyberpunk 2077, Terminator 2D, Ghosts'n Goblins Resurrection) in seeded data.

Round 6 of the 2026-05-17 validation session (filter token → DB slug collapse
families, ADR-less, captured in `design.md`) clarified how platform chip tokens
expand to multiple IGDB platform slugs at the filter layer. Round 7 delivered a
comprehensive rule set covering all chip interactions and requires a significant
rewrite of `Games::Filter` to support four independent axes, per-platform
binding for ownership / engagement, and bidirectional cascade in the UI.

The rule set is large enough — and the implementation cost high enough — that it
earns its own ADR rather than living inside a session log entry.

## Decision

The filter implements **four orthogonal axes** combined with **within-axis OR**
and **cross-axis AND**, with **per-platform binding** when the platform axis
intersects with ownership or engagement, and **bidirectional cascade** in the UI
driven by a set of implies / mutex rules.

### Axes (4)

1. **Lifecycle** = {`released`, `scheduled`} — released XOR scheduled per game
   (no game is both).
2. **Ownership** = {`owned`, `wishlist`} — `wishlist` ≡ NOT owned globally.
3. **Engagement** = {`played`} — single chip; user plays a game on EXACTLY ONE
   platform. Data: `games.played_at` timestamp plus a new
   `games.played_platform_id` FK to `platforms`.
4. **Platform** = {`ps5`, `switch2`, `steam`} — multi-select; tokens map to
   multiple underlying IGDB platform slugs via `TOKEN_TO_PLATFORM_SLUGS`
   (collapse families documented in `design.md ### Platform Chips`).

### Logical combinators

- **Within axis: OR.**
  - `released + scheduled` = any lifecycle (effectively the axis is inactive —
    every game passes).
  - `owned + wishlist` = all ownership states (every game passes ownership per
    rule f).
  - `ps5 + switch2` = available on either platform family.
- **Across axes: AND.**
  - `released + owned` = released AND owned.
- **Per-platform binding** when the platform axis intersects with ownership or
  engagement axes:
  - `owned + <platform>` ≡ owned ON that platform (`PlatformOwnership` join
    scoped to expanded slugs).
  - `played + <platform>` ≡ played ON that platform
    (`played_platform_id IN expanded_db_slugs`).
  - `wishlist + <platform>` ≡ not-owned-globally AND game has the platform in
    availability. Wishlist is ALWAYS global ("doesn't own ANYWHERE") — never
    per-platform.
  - `released / scheduled + <platform>` ≡ lifecycle filter AND game has the
    platform available.

### Implies / mutex (rules a–f)

- **(a)** `played → released + owned` (auto-check parents on check).
- **(b)** `owned → released` (auto-check on check).
- **(c)** `wishlist ⊥ played` ONLY when `owned` is not also checked (CONDITIONAL
  mutex). `owned + played + wishlist` is VALID because `owned` still satisfies
  played's requirement.
- **(d)** `scheduled + owned` valid (preorder semantics).
  `scheduled + owned + played` invalid (played needs released, which is mutually
  exclusive with scheduled per rule e).
- **(e)** `released ⊥ scheduled` per game (XOR). Both checked = lifecycle filter
  inactive (every game passes the axis).
- **(f)** `owned ∪ wishlist` covers the ownership universe. Both checked = no
  ownership filter (every game passes the ownership axis).

### Cascade (bidirectional corrective)

- **CHECK cascade.** Checking a child auto-checks its parents (partly in place
  per spec 06).
- **UNCHECK cascade.** Unchecking a parent re-validates children; if a child's
  dependencies are no longer satisfied, auto-uncheck the child.

**Worked example (user-provided):**

1. Start: nothing checked.
2. Check `played` → cascade auto-checks `released + owned` plus at least one
   platform chip.
3. Then check `wishlist` → `played` stays (owned still checked, still satisfies
   played's requirement per rule c).
4. Then uncheck `owned` → `played` auto-unchecks (only `wishlist` remains for
   ownership, which is mutex with `played` when `owned` is absent).

### Recorded chip — DROPPED

User direction: "drop recorded as played and recorded is the same thing."
`recorded` is subsumed by `played`. Remove:

- `Games::RecordedChipComponent`
- The "recorded" row on `/games/:id` ownership section (Wave C4 addition)
- Any `recorded`-related filter token

## Implementation contract

- **Data:** new `games.played_platform_id` FK to `platforms` (single platform
  per played game; user plays on exactly one platform). Backfill is manual —
  column starts NULL on every existing row; user will set values per game from
  the detail page.
- **Code:**
  - Rewrite `app/queries/games/filter.rb` (`Games::Filter`) end-to-end to
    implement the four-axis logic, within-axis OR, cross-axis AND, and
    per-platform binding for ownership / engagement.
  - Rewrite `app/javascript/controllers/games_filter_controller.js` (or the
    equivalent Stimulus controller) for bidirectional cascade.
  - Drop `app/components/games/recorded_chip_component.rb` and its view
    template.
  - Update `app/views/games/show.html.erb` ownership section to remove the
    recorded row.
- **UI (deferred):** UI to set `played_platform_id` per game on the detail page.
- **Specs (Wave F consolidation):** comprehensive `Games::Filter` spec covering
  every combo from the worked examples plus edge cases — full four-axis decision
  table.

## Worked examples (test cases for Wave F)

| URL filter set                                                   | expected behavior                                                                                                               |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `?filters=released,scheduled,owned,wishlist,switch2` (no played) | all Switch-family games (5 in seeded data — Pragmata, Mandragora, Cyberpunk 2077, Terminator 2D, Ghosts'n Goblins Resurrection) |
| `?filters=played,ps5`                                            | games user played on PS5 (`played_platform_id` in PS5 slug set)                                                                 |
| `?filters=wishlist,steam`                                        | games user doesn't own globally AND available on Steam family                                                                   |
| `?filters=scheduled,switch2`                                     | games scheduled (not yet released) AND available on Switch family                                                               |
| `?filters=released,wishlist,ps5`                                 | released AND not-owned-globally AND available on PS5                                                                            |
| `?filters=owned,played,wishlist`                                 | every game passes ownership (rule f) AND `played_at` set somewhere — `played` stays valid because `owned` is present (rule c)   |

## Consequences

- **Code surface.** `Games::Filter` is rewritten; the existing controller-level
  chip toggle stays but the filter Stimulus controller gains bidirectional
  cascade logic. A new migration adds `games.played_platform_id`. Component /
  view trims for the dropped `recorded` chip.
- **Spec surface.** Wave F adds a comprehensive `Games::Filter` decision- table
  spec; existing spec 06 (filter row) is amended to point at this ADR for the
  authoritative semantics instead of duplicating them.
- **UX.** Bidirectional cascade prevents invalid combos from rendering as empty
  result sets — chips that would produce zero matches are auto- unchecked
  instead.
- **Data lifecycle.** `played_platform_id` starts NULL across the board; user
  backfills manually from the detail page. Past `played_at` timestamps remain
  valid but carry no platform binding until set.
- **Follow-ups opened.**
  - UI to set `played_platform_id` per game on `/games/:id`.
  - Comprehensive `Games::Filter` Wave F spec.
  - Update spec 06 (filter row) reference to point at this ADR.

## Date

2026-05-17

## Related

- `docs/design.md ### Platform Chips` — platform chip token → DB slug collapse
  families (round 6 of the 2026-05-17 validation session).
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/log.md` —
  round 7 entry capturing the lock-in.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs-v2/06-*`
  — spec 06 (filter row); to be amended to reference this ADR.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md` —
  Wave F (consolidation) holds the `Games::Filter` decision-table spec.
