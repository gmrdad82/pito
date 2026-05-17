# ADR 0014 — Platform chip generation collapse

## Status

Accepted, 2026-05-17. [skipci]

## Context

The `/games` filter chips + display chips initially had per-generation
separation (PS5, PS4, Switch, Switch 2, Xbox, etc.). User clarified 2026-05-17
that this creates confusion — a user owns a console FAMILY (PS5 hardware plays
PS4 games via backwards compat; Switch 2 plays Switch gen 1 games), not a
specific generation.

## Decision

**Three family chips total: `ps`, `switch`, `steam`.** Each chip represents a
console / store family, NOT a specific generation. Xbox excluded entirely.

### Family → IGDB ids

| family chip | label  | brand color            | covers IGDB ids                              | rationale              |
| ----------- | ------ | ---------------------- | -------------------------------------------- | ---------------------- |
| `ps`        | PS     | #003791 (PS blue)      | 167 (PS5), 48 (PS4)                          | PS5 hardware plays PS4 |
| `switch`    | Switch | #E60012 (Nintendo red) | 508 (Switch 2), 130 (Switch gen 1)           | Switch 2 plays gen 1   |
| `steam`     | Steam  | #00ADEE (Steam cyan)   | 6/3/14/13/92 (PC family) + native steam slug | PC ecosystem           |

### Why no per-generation distinction

- User owns the FAMILY (the PS5 console covers both PS4 + PS5 games)
- Display: one chip per family avoids visual noise (a multi-platform game shows
  3 chips max, not 5+)
- Filter: one token per family avoids "ps4 AND ps5" filter cardinality
- Browsing: "what's on PS this generation cycle" is the user mental model, not
  "what's exclusively PS5 vs PS4"

### Code locations

- `app/models/platform.rb` `IGDB_ID_TO_CANONICAL_SLUG` — IGDB id → family slug
  mapping (the collapse layer)
- `app/components/platforms/chip_component.rb` `SLUG_BRAND` — chip rendering
- `app/queries/games/filter.rb` `TOKEN_TO_PLATFORM_SLUGS` — filter token → DB
  slugs
- `app/helpers/platform_logos_helper.rb` `KNOWN_LOGOS` — display set

### Xbox exclusion

User chose to exclude Xbox entirely 2026-05-17 ("I don't care about Xbox"). No
`xbox` chip slug, no `xbox` filter token. Games with Xbox platforms ignore those
IGDB ids in chip rendering. Future Xbox re-inclusion is reversible — add `xbox`
to all three code locations above, mapping IGDB ids 49 (Xbox One), 169 (Series
X|S), 11 (Xbox), 12 (Xbox 360) to slug `xbox`.

### Backward compat

URL bookmarks using old `?filters=ps5,switch2,steam` tokens will silently fall
through the whitelist (treated as unknown). Single-user project — acceptable.
Document as breaking change.

## Consequences

- A game on ONLY PS4 renders the PS chip (not "PS4").
- A game on ONLY Switch gen 1 renders the Switch chip (not "Switch 1").
- A game on BOTH PS4 + PS5 still renders only ONE PS chip (no duplicate).
- A new console generation (e.g., PS6, Switch 3) gets added to the `ps` /
  `switch` slug groups without needing a new chip.
- A new family (e.g., Apple Vision Pro) would warrant a new family chip plus a
  new filter token.

## Related

- ADR 0013 — `/games` filter semantics (filter axis + per-platform binding).
- `docs/design.md` — `### Platform Chips` table + `### Filter semantics`
  collapse table both render the same three family slugs.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/log.md` —
  round 10 (collapse decision) + round 11 (slug rename + ADR promotion).
