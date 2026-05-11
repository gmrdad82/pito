# Phase 27 — Games Listing Rework: Shelves, Filter Row, Display Modes, Per-Platform Ownership

> Read `docs/plans/beta/beta.md` first. Then read this `plan.md`. Then read the
> umbrella spec at `specs/01-overview-games-listing-rework.md` and the seven
> sub-specs in order.

---

## Goal

Rework `/games` from a single flat grid into a denser, more navigable surface:
two top shelves (Genres, Collections), a multi-select Filter Row with
platform-aware semantics, three Display Modes (Grid / List / Shelves-by-letter)
with persisted user preference, and per-platform ownership replacing the single
`platform_owned_id` pointer on `Game`.

The phase also introduces a `Platform` model (sourced from IGDB), a
`game_platform_ownerships` join table, an explicit `:shelf` cover-art variant
(65% of grid, pipeline-rendered — no browser-resize), and MCP / CLI parity for
the new plural ownership shape and the filter row.

Source-of-truth note (Mobile drop, verbatim):
`docs/notes/2026-05-11-11-26-17-games-listing-shelves-filters-display-modes.md`.

---

## Scope

In scope:

- New `platforms` table (FriendlyId slug, IGDB platform id, abbreviation).
- New `game_platform_ownerships` join table — per-platform ownership of a game.
- Filter row component with multi-select chip state in URL params
  (`?filters=recorded,ps5,owned`), platform-aware semantics, clear-all link.
- Genres and Collections shelves at the top of `/games`, alphabetical,
  horizontal-scroll skinned.
- Display mode switcher (Grid / List / Shelves-by-letter), persisted via a new
  `User#preferred_games_display_mode` enum.
- List mode with alpha-grouped sticky letter headings and a sortable column set.
- Shelves-by-letter mode (empty letters hidden).
- Explicit `:shelf` cover-art variant rendered server-side (65% of grid size).
- Game show + edit screens gain a per-platform ownership editor.
- MCP `game_update_local` accepts plural `platform_owned_ids: [int]` (singular
  `platform_owned_id` auto-wrapped for back-compat).
- CLI filter parity in the `pito` TUI Games view.
- Saved-view kind `games` is extended to carry the active filter set and display
  mode (final integration locked in `01d`).

Out of scope:

- IGDB game-data sync changes beyond pulling `platforms` (no metadata refresh
  redesign).
- Re-styling the existing horizontal-scroll skin.
- Adding `acquired_at` / `store` / `notes` fields beyond the agreed v1 columns
  (see open question in `01a`).
- Multi-user permission changes (single-install + multi-user stands; see
  `docs/decisions/0003-drop-tenant-single-install-multi-user.md`).
- Touching any other listing (`/channels`, `/videos`, `/projects`, etc.).

---

## Locked decisions (master agent)

1. **Shelf cover variant size: 65%** of grid (≈ 152 × 203 px against the current
   234 × 312 grid). Architect's recommendation per the user's challenge — "50%
   may be too aggressive." Explicit `:shelf` variant in the cover-rendering
   pipeline; never browser-resize / CSS scaling.
2. **Per-platform ownership table: `game_platform_ownerships`** —
   `id, game_id, platform_id (FK), acquired_at (nullable), store (string, nullable, free-text for now), notes (text, nullable), timestamps`.
   Unique on `(game_id, platform_id)`. (See `01a` open question on whether to
   ship `acquired_at` / `store` / `notes` in v1 or defer to a metadata
   follow-up.)
3. **Platform model: `Platform`** —
   `id, name, slug (FriendlyId), igdb_platform_id (unique), abbreviation, timestamps`.
   Names pulled from IGDB on first sync; phase introduces an initial seed + a
   Sidekiq sync job.
4. **Filter row component: `FilterRowComponent`** — multi-select chips. State in
   URL (`?filters=recorded,ps5,owned`). Click toggles a chip. `[clear all]` link
   appears once at least one filter is active. Empty filter row = show
   everything (locked).
5. **Platform filter precedence** (verbatim from source note §2):
   - Platform filters apply to the platform the user actually owns the game on.
   - For unreleased / not-yet-owned games, the platform filter still matches if
     the game is scheduled on that platform.
   - If the user owns the game on at least one platform, the platform filter
     matches only the platforms the user owns it on.
6. **Filter definitions:**
   - `recorded` — `game.videos.exists?` (linked Video records).
   - `released` — IGDB `first_release_date` in the past.
   - `scheduled` — IGDB `first_release_date` in the future.
   - `owned` / `not owned` — presence / absence of any
     `game_platform_ownerships` row.
7. **Display mode persistence:** `User#preferred_games_display_mode` enum
   (`grid`, `list`, `shelves_by_letter`). Default `grid`. URL param
   `?display=list` may override per-request but does not persist unless the user
   clicks a switcher button.
8. **Display mode switcher:** small control top-right of `/games`, above the
   filter row. Three bracketed-link buttons `[grid]` `[list]` `[shelves]`.
9. **List mode columns:** cover thumb, title, platforms owned, genres, status.
   Sortable. Sticky letter group headings.
10. **Shelves-by-letter:** one shelf per letter; empty letters hidden (per
    source-note lean).
11. **MCP `game_update_local`:** `platform_owned_ids: [int]` plural. Old
    singular `platform_owned_id: int` accepted and auto-wrapped to a one-element
    array for back-compat. Boundary stays yes/no for booleans.

---

## Cross-stack scope

| Surface              | In scope this phase                                          |
| -------------------- | ------------------------------------------------------------ |
| Rails web (`/games`) | YES — full rework (shelves, filter row, three modes, editor) |
| Rails MCP            | YES — `game_update_local` plural; filter parity              |
| `pito` CLI (Rust)    | YES — TUI Games view gets the filter row + plural ownership  |
| Cloudflare website   | NO — marketing surface untouched                             |

---

## Sequencing

Per the Mobile note's dispatch list:

1. **01a — Per-platform ownership data model.** Blocking for filter semantics
   and the show/edit editor. Introduces `Platform`, `GamePlatformOwnership`,
   `game_id ↔ platform_id` unique constraint, IGDB platform sync, factories,
   model specs.
2. **01b — Filter row + platform semantics.** Depends on `01a`. Introduces
   `FilterRowComponent`, `Games::Filter` query object, URL state, request +
   component + system specs for the full filter-combination matrix.
3. **01c — Genres and Collections shelves.** Parallel with `01b`. Top-of-page
   two horizontal shelves, alphabetical, skinned-scroll, `:shelf` cover variant.
4. **01d — Display mode switcher + three modes.** Parallel with `01b` / `01c`.
   Adds `User#preferred_games_display_mode`, the switcher control, Grid / List
   (alpha-grouped) / Shelves-by-letter modes.
5. **01e — Shelf cover art variant.** Parallel with everything. Adds the
   explicit `:shelf` variant entry to the cover-rendering pipeline at 65% of
   grid size.
6. **01f — Game show/edit per-platform ownership UI.** Depends on `01a`. Editor
   checklist of platforms (sourced from IGDB), tick the ones owned; plumbing the
   per-platform metadata (per `01a` v1 decision).
7. **01g — MCP / CLI parity + `game_update_local` plural.** Depends on `01a` and
   `01b`. Extends MCP tool to plural; filter parity for CLI + MCP.

---

## Checkboxes

### 01a — Per-platform ownership data model

- [ ] Migration: create `platforms` (slug FriendlyId, `igdb_platform_id` unique,
      abbreviation, name).
- [ ] Migration: create `game_platform_ownerships` (game_id, platform_id,
      acquired_at, store, notes; unique on `(game_id, platform_id)`).
- [ ] Models: `Platform`, `GamePlatformOwnership`, associations on `Game`.
- [ ] Factory: `platforms`, `game_platform_ownerships`.
- [ ] Service: `Platforms::SyncFromIgdb` (one-shot + idempotent).
- [ ] Job: `Platforms::SyncFromIgdbJob` wrapping the service.
- [ ] Seed: ensure PS5, Switch 2, Steam, GOG, Epic exist by slug at boot.
- [ ] Model specs: validations, associations, scopes, uniqueness, friendly_id.
- [ ] Service spec, job spec.
- [ ] Drop / repurpose decision for legacy `games.platform_owned_id` (see open
      question 3 in this plan).

### 01b — Filter row + platform semantics

- [ ] `FilterRowComponent` with chip rendering, `[clear all]` link.
- [ ] `Games::Filter` query object — composes scopes for each filter token.
- [ ] URL param parser / serializer for `?filters=token1,token2`.
- [ ] Scopes on `Game`: `recorded`, `released`, `scheduled`, `owned`,
      `not_owned`, `on_platform(slug)`, `owned_on_platform(slug)`.
- [ ] Platform-precedence combinator (matches §2 of source note exactly).
- [ ] yes/no boundary on boolean URL inputs (none in v1; reserved guard).
- [ ] Model + query-object + component + request + system spec sweep.

### 01c — Genres and Collections shelves

- [ ] `Games::GenresShelfComponent`, `Games::CollectionsShelfComponent`.
      (Master dispatch elected partials over ViewComponents — see
      `app/views/games/_genres_shelf.html.erb` /
      `_collections_shelf.html.erb`.)
- [x] Alphabetical ordering.
- [x] Use existing skinned horizontal-scroll partial / classes.
- [ ] Tile = `:shelf` cover variant (depends on `01e`).
      (Shipped as inline 75×100 px tile per master's 50% addendum; the
      `:shelf` cover variant from `01e` will replace the inline block
      once that lands.)
- [x] Component specs, system spec.
      (`spec/system/games_index_spec.rb` + 12 added request specs in
      `spec/requests/games_spec.rb` under "Phase 27 §01c —".)

### 01d — Display mode switcher + three modes

- [x] Migration: add `users.preferred_games_display_mode` (integer enum, default
      0 / `grid`).
- [x] Model: enum on `User` (`grid`, `list`, `shelves_by_letter`).
- [x] `Games::DisplayModeSwitcherComponent` — three bracketed-link buttons.
      (Delivered as the `games/_display_mode_switcher` partial per master
      dispatch; component-vs-partial reframe noted in the session log.)
- [x] Persist on click (PATCH `/users/games_preferences`). (Master-dispatch
      reframed the URL from `/settings/games_display_mode/:mode` to the
      `users` namespace — see session log.)
- [x] Grid view (existing). (Extracted into `games/_grid_mode` for branching.)
- [x] List view — alpha-grouped, sticky letter headings, sortable columns (cover
      thumb, title, platforms owned, genres, status). (Sort-column UI deferred
      until 01a's per-platform ownership shape stabilises; structure +
      letter-head sticky CSS landed.)
- [x] Shelves-by-letter view — one shelf per letter, empty letters hidden.
- [x] yes/no boundary not applicable (no boolean inputs).
- [x] Model + request + view + component + system spec sweep. (System spec
      deferred — see session log; the surface is exercised by view + request
      specs while the controller index is wedged on 01a / 01c drift.)

### 01e — Shelf cover art variant

- [ ] Add `:shelf` variant entry to the cover-rendering pipeline at 65% of grid
      (~152 × 203 px).
- [ ] Update the cover-art ViewComponent / helper to accept `variant: :shelf`.
- [ ] Asset pipeline + tests confirm size + cache key differ from `:grid`.
- [ ] Component spec covering both variants.

### 01f — Game show/edit per-platform ownership

- [ ] On `Game#show`: list platforms the game is released on (from IGDB), with
      ownership state indicators.
- [ ] On `Game#edit`: checklist of release platforms; tick the ones owned.
- [ ] Form submits to a nested controller `Games::PlatformOwnershipsController`
      (`PUT /games/:slug/platform_ownerships`).
- [ ] Friendly URL preserved.
- [ ] No JS confirm — destructive un-tick of "owned" goes through the in-form
      submit (no separate confirmation page is needed for ownership toggles;
      delete-all goes through `/deletions/...` per project rule).
- [ ] Request + system + view spec sweep.

### 01g — MCP / CLI parity

- [ ] MCP `game_update_local` accepts `platform_owned_ids: [int]`.
- [ ] Singular `platform_owned_id: int` auto-wrapped to one-element array.
- [ ] yes/no boundary on every boolean argument.
- [ ] MCP tool spec — singular accepted, plural accepted, mixed rejected.
- [ ] CLI TUI Games view gains the same filter chip set + plural ownership.
- [ ] Rust tests for the CLI surface.

---

## Open questions (surfaced for master agent)

1. **`acquired_at` / `store` / `notes` columns** — ship in v1, or keep a
   skeleton `(game_id, platform_id)` table and defer metadata to a follow-up?
   Architect leans v1 since the columns are nullable and cheap; the editor UI
   can ship with the basics and fill in metadata fields later.
2. **Filter chip default state** — all chips off (show everything) or all chips
   on (show everything explicitly)? Architect leans "all off" per the source
   note's "Empty filter row = show everything."
3. **Existing `games.platform_owned_id`** — drop in this phase, or keep as a
   derived "primary platform" pointer to one of the ownerships? Architect leans
   drop, since the user note treats the new join table as the authoritative
   shape and any "primary" notion can be reintroduced later.
4. **Saved-view integration** — does display-mode + filter row persist via the
   existing saved-view system, OR a separate user preference, OR both? Source
   note says "saved-view system or user preference." Locked decision is
   `User#preferred_games_display_mode` for the user-level default; saved-views
   still capture the filter+display URL state per view.
5. **Sticky letter headings on list mode** — JS-driven (IntersectionObserver for
   swap-in highlights) or pure CSS `position: sticky`? Architect leans pure CSS
   for simplicity; JS only if there's a UX gap.
6. **"(none)" placeholder for empty letters in shelves-by-letter** — hide
   (source note's lean) or show with placeholder? Locked: **hide**.
7. **IGDB platform sync trigger** — on phase startup migration, on each game
   create, or via a rake task? Architect leans seed + Sidekiq job
   (`Platforms::SyncFromIgdbJob`) cron-scheduled weekly; rake task for manual
   one-off refresh.
8. **Shelf cover variant pixel size** — 65% locked. Concretely 152 × 203 px
   against the current 234 × 312 grid. (`01e` carries the asset-pipeline
   detail.)

---

## Quality gates

Standard Beta gates (see `beta.md` §"Per-phase quality gates"). Additional
phase-specific checks:

- Every spec in this phase carries the full pyramid sweep (model / service / job
  / component / helper / validator / lib / MCP / request / system) per
  `docs/agents/architect.md` rule D.
- yes/no boundary applied at every external boolean: URL params, JSON, MCP I/O,
  CLI args.
- No `alert` / `confirm` / `prompt` / `data-turbo-confirm` anywhere. Ownership
  destructive un-ticks go through the form submit; deletion of a `Game` itself
  continues to route through `/deletions/...`.
- Friendly URLs preserved across all touched routes.
- Brakeman + bundler-audit + Dependabot triage clean.

---

## Manual test recipe (high-level)

A detailed recipe per sub-spec lives in the relevant `specs/01*.md` file. The
phase-level smoke test:

1. `bin/setup` (fresh DB) → `bin/rails db:seed` to populate platforms.
2. `bin/dev` → open `http://localhost:3000/games`.
3. Confirm two shelves render at the top (Genres, Collections), alphabetical,
   horizontally scrollable, with `:shelf`-sized covers.
4. Confirm the filter row renders below with chips
   `[recorded] [released] [owned] [not owned] [scheduled] [ps5] [switch2] [steam] [gog] [epic]`.
5. Click `[ps5]` — URL becomes `?filters=ps5`. The grid filters down. A
   `[clear all]` link appears.
6. Click `[owned]` — URL becomes `?filters=ps5,owned`. The grid narrows further
   to games owned on PS5 specifically.
7. Top-right of `/games`, click `[list]` — view switches to alpha-grouped list.
   Refresh — list mode persists for the user.
8. Click `[shelves]` — letter shelves render, empty letters hidden.
9. On any game `show` page, edit per-platform ownership; PS5 + Steam ticked
   shows up correctly in the filter row.
10. From the `pito` CLI, the Games view renders the same chip set; toggling
    `ps5` filters server-side via MCP.

Detailed per-step expected values land in the per-spec manual recipes.

---

## References

- `docs/notes/2026-05-11-11-26-17-games-listing-shelves-filters-display-modes.md`
  (source-of-truth Mobile drop).
- `docs/agents/architect.md` — spec pyramid, pane primitives, yes/no boundary.
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — auth model.
- `docs/design.md` — bracketed-link convention, monospace style, no red outside
  destructive actions.
- `CLAUDE.md` — hard rules (no JS confirm, bulk-as-foundation, secrets in
  credentials).
