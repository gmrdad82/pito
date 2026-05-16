# Phase 28 — Multi-Version Game Grouping

> Read `docs/plans/beta/beta.md` first. Then read this `plan.md`. Then read the
> single v1 sub-spec at `specs/01a-multi-version-game-grouping.md`.

---

## Goal

Group different editions of the same game — "Pragmata", "Pragmata Deluxe
Edition", "Pragmata Standard Edition" — under a single logical title with
multiple editions. Today every edition is an independent `Game` row, so the
games listing fragments and the per-edition ownership data is scattered across
duplicates that look like distinct titles.

Phase 28 introduces a self-referential parent / edition relationship on `Game`
(`version_parent_id`, `version_title`), wires the IGDB importer to populate it
from IGDB's own `version_parent` field, makes the games index display only
primaries (with an editions badge), and exposes the relationship across show /
edit, MCP, and CLI.

This is a v1 scoped phase: one sub-spec (`01a`), no parallel lanes. If the user
asks for more (e.g. richer aggregation rules, a dedicated editions admin
surface, etc.), follow-up sub-specs land as `01b`, `01c`, etc.

Source-of-truth (user direction, verbatim): "Also did you address multiple
version of the same game like Pragmata and Pragmata Deluxe?"

---

## Scope

In scope:

- `games.version_parent_id` (self-referential FK, nullable) +
  `games.version_title` (string, nullable) columns.
- `Game` associations / scopes / validations: `version_parent`, `editions`,
  `Game.primaries`, `Game.editions_of(game)`. One level of nesting only — a game
  cannot be both a parent and an edition.
- IGDB importer pre-resolves the parent and stamps `version_parent_id` on
  edition rows. Idempotent re-imports do not create sibling chains.
- Games index (grid / list / shelves-by-letter / by-letter) shows primaries
  only; primaries with `editions.count > 0` get an `+N editions` badge.
- Game show page lists editions as a sub-section; per-edition ownership stays
  independent (no inheritance).
- Game edit page exposes `version_parent_id` (typeahead picker) and
  `version_title` (free text). Detaching sets `version_parent_id` to nil.
- MCP `games_list` returns primaries by default; adds `include_editions: yes/no`
  argument (yes/no boundary). MCP `game_show` surfaces the editions list and the
  parent pointer.
- CLI `pito` TUI Games view renders the same primaries-only listing with the
  badge and a drill-down into editions.
- One-shot rake-task backfill for existing games whose titles match common
  edition patterns ("Deluxe Edition", "Standard", "Game of the Year", "GOTY",
  "Collector's"). Idempotent + safe to re-run.

Out of scope:

- Multi-level nesting (edition of an edition).
- Automatic inheritance of genres / platforms / ownership from parent to edition
  or vice versa.
- A dedicated admin / merge UI for batch-grouping editions (open question — may
  surface as a 01b follow-up).
- Re-modeling `Bundle` semantics. Bundles continue to bundle individual `Game`
  rows; editions inside a bundle are not collapsed.

---

## Locked decisions (master agent)

1. **At most one level of nesting.** A game cannot be both a parent and an
   edition. Enforced by validation: `version_parent_id` must be `nil` when the
   row has any `editions`, and the chosen parent must itself have a `nil`
   `version_parent_id`.
2. **No inheritance.** Editions own their own genres, platforms,
   `game_platform_ownerships`, videos, footages, calendar entries. The parent is
   purely a grouping + display anchor.
3. **Primaries-only by default in every listing surface.** Games index, MCP
   `games_list`, CLI TUI Games view all default to primaries. The
   `include_editions: yes/no` boundary flips the listing.
4. **Aggregated ownership rollup on the parent.** `Game#owned_platforms` for a
   primary returns the union of its editions' owned platforms PLUS its own
   ownerships. `Game#owned_editions(platform)` lists editions you own on a given
   platform. Scope inputs land in `01a`.
5. **Edge case — primary itself owned.** A primary can also have its own
   `game_platform_ownerships` rows (the user may own the "base" edition
   separately). Rollup unions parent + editions; no special-casing.
6. **Friendly URLs unchanged.** Edition rows keep their existing `igdb_slug`
   /`id` URL. The parent owns its own URL; editions stay reachable directly.
7. **Detach is non-destructive.** Setting `version_parent_id = nil` on an
   edition row leaves the row in place; it just becomes a primary again. The
   editions association on the (now orphan) former parent uses
   `dependent: :nullify`.
8. **Badge copy:** `+N editions` (singular `+1 edition`). Bracketed-link style
   per `docs/agents/architect.md` rule A — no inner padding spaces. Click target
   scrolls to the editions section on the parent's show page.

---

## Cross-stack scope

| Surface              | In scope this phase                                       |
| -------------------- | --------------------------------------------------------- |
| Rails web (`/games`) | YES — listing rollup + show editions section + edit       |
|                      | path + detach                                             |
| Rails MCP            | YES — `games_list include_editions`, `game_show` editions |
| `pito` CLI (Rust)    | YES — TUI Games view primaries-only + drill-down          |
| Cloudflare website   | NO                                                        |

---

## Sequencing

A single v1 sub-spec covers the full slice; no parallel lanes.

1. **01a — Multi-version game grouping (v1).** Migration + model + IGDB
   importer + listing rollup + show / edit / detach + MCP + CLI + backfill rake
   task. Full spec pyramid (model / service / job / component / helper / request
   / system / MCP / CLI) per `docs/agents/architect.md` rule D.

Future (NOT scheduled — surface as follow-up if the user wants more):

- 01b — Admin "merge editions" surface for bulk grouping after the fact.
- 01c — Smarter aggregation (release-year rollups, "completed any edition" state
  on the parent).

---

## Checkboxes

### 01a — Multi-version game grouping (v1)

- [x] Migration: add `games.version_parent_id` (bigint, nullable, FK to
      `games.id`, indexed) and `games.version_title` (string, nullable).
- [x] Foreign key `ON DELETE SET NULL` so destroying a parent leaves its
      editions in place as orphan primaries.
- [x] Model: `Game.belongs_to :version_parent, optional: true`,
      `Game.has_many :editions, foreign_key: :version_parent_id, dependent: :nullify`.
- [x] Model: scopes `Game.primaries`, `Game.editions_of(game)`,
      `Game.with_editions`.
- [x] Model: validation — `version_parent_id` absent when `editions.any?`;
      chosen parent must itself be a primary; no self-reference; no cycle.
- [x] Model: `Game#owned_platforms` rollup (parent unions self + editions);
      `Game#owned_editions(platform)`.
- [x] IGDB importer: pre-resolve the parent (create-if-missing) before stamping
      `version_parent_id`; idempotent re-import.
- [x] Games index: render only primaries across grid / list / shelves /
      by-letter; render `+N editions` badge on primaries with editions.
- [x] Game show: editions sub-section listing each edition with its own
      ownership chip strip.
- [x] Game edit: typeahead picker for `version_parent_id` (value-as-id);
      free-text `version_title`; detach submits `version_parent_id = nil`.
- [x] MCP `games_list`: defaults to primaries; `include_editions: yes/no`
      argument flips the listing.
- [x] MCP `game_show`: returns `version_parent_id`, `version_title`, and
      `editions: [...]` for primaries.
- [ ] CLI TUI Games view: primaries-only by default; drill-down shows editions;
      `+N editions` badge rendered. _(deferred to `pito-rust` follow-up — Rails
      lane shipped, CLI half tracked separately.)_
- [x] yes/no boundary applied at every external boolean.
- [x] Backfill rake task `games:backfill_version_parents` — regex-driven
      ("Deluxe Edition", "Standard Edition", "Game of the Year", "GOTY",
      "Collector's"); idempotent; safe to re-run.
- [x] Spec pyramid sweep (model / service / job / component / helper / request /
      system / MCP / rake). _(CLI lane deferred.)_

---

## Open questions (surfaced for master agent)

1. **Parent release year vs. earliest-edition release year.** When a parent row
   is auto-created from IGDB metadata and the user has no edition with a release
   date, do we (a) default the parent's `release_date` to the earliest edition's
   date, or (b) leave it nil and rely on whichever edition the user clicks for
   date display? Architect leans (a) — derive on save via an `after_save` hook
   on `Game` editions, last-write-wins from the earliest edition. Surface for
   user lock before dispatch.
2. **Typeahead source for the edit picker.** Search by title only, or also match
   IGDB ID prefix? Architect leans title-only (typeahead matching `LOWER(title)`
   with `ILIKE '%query%'`), capped at 20 results, primaries only (an edition
   cannot itself parent another edition).
3. **What happens to a parent with zero editions after detach?** Architect leans
   nothing — the parent stays a primary, no automatic delete. It can be merged
   back later via the edit picker on either side.
4. **Backfill scope.** Run on the existing dev DB only via rake, or also as part
   of `db/seeds.rb` for new installs? Architect leans rake-only; seeds stay
   deterministic.
5. **Bundle interaction.** A `Bundle` may include both the parent and an edition
   row of the same logical title. Do we de-dupe at display time, or let the user
   see both? Architect leans "display both" — the bundle is the user's explicit
   grouping; we don't second-guess it. Surface for confirmation.

---

## Quality gates

Standard Beta gates (see `beta.md` §"Per-phase quality gates"). Additional
phase-specific checks:

- Full spec pyramid sweep per `docs/agents/architect.md` rule D.
- yes/no boundary applied at every external boolean (URL params, JSON, MCP I/O,
  CLI args).
- No `alert` / `confirm` / `prompt` / `data-turbo-confirm`. Detach goes through
  the edit form submit; deletion of a `Game` continues to route through
  `/deletions/...`.
- Friendly URLs preserved across all touched routes.
- Brakeman + bundler-audit + Dependabot triage clean.
- Idempotent migrations + idempotent backfill rake task.

---

## Manual test recipe (high-level)

A detailed recipe lives in `specs/01a-multi-version-game-grouping.md`. The
phase-level smoke test:

1. `bin/rails db:migrate` — confirm `version_parent_id` + `version_title` land
   on `games`.
2. `bin/rails db:seed` (no behavior change expected).
3. `bin/rails runner 'g = Game.create!(title: "Pragmata"); e = Game.create!(title: "Pragmata Deluxe Edition", version_parent: g, version_title: "Deluxe"); puts g.editions.count'`
   → `1`.
4. `bin/dev` → `http://localhost:3000/games` — only "Pragmata" tile renders (not
   the Deluxe row); the tile shows a `+1 edition` badge.
5. Click the Pragmata tile → show page renders an "Editions" sub-section with
   the Deluxe row.
6. Edit the Deluxe row → set `version_parent_id` to nil → save. Refresh `/games`
   — both Pragmata and Pragmata Deluxe Edition render as primaries.
7. Re-attach via edit form. Confirm IGDB re-import of either row does not create
   duplicates (run `rake games:resync_one[<igdb_id>]` or whichever sync
   entrypoint the importer surfaces).
8. From `bin/rails runner`, call MCP `games_list` with `include_editions: 'no'`
   → primaries only; `include_editions: 'yes'` → flat list including editions.
9. From the `pito` CLI, Games view shows primaries only by default; drilling
   into Pragmata shows the Deluxe edition.
10. Run `rake games:backfill_version_parents` against a fixture set with "Halo
    3", "Halo 3 (Game of the Year)", "Halo 3 Anniversary Edition" — confirm the
    GOTY + Anniversary rows attach under "Halo 3" without creating a third "Halo
    3" row.

---

## References

- User direction (verbatim): "Also did you address multiple version of the same
  game like Pragmata and Pragmata Deluxe?"
- `app/models/game.rb` — current `Game` shape; Phase 14 + 27 columns documented
  in the model header.
- `app/services/igdb/` — existing IGDB import service surface.
- `docs/agents/architect.md` — spec pyramid (rule D), bracketed-link rule (A),
  yes/no boundary (E).
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — auth model.
- `docs/design.md` — bracketed-link convention, monospace style, no red outside
  destructive actions.
- `CLAUDE.md` — hard rules (no JS confirm, bulk-as-foundation, secrets in
  credentials).
