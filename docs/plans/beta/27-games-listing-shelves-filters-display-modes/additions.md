# Phase 27 — additions

Scope-drift ledger for `/games` revamp work that SHIPPED but was NOT part of
the original `plan.md` checkboxes (01a–01g). Each entry traces back to a log
session or commit. Append-only; sorted structural-first, polish-last.

## Models / data

## 2026-05-11 — primary-genre pin migration

- **Item:** `games.primary_genre_id` column + `Game#primary_genre`
  association + `Games::PrimaryGenrePicker` service + backfill rake task
  (`pito:backfill_primary_genres`).
- **Rationale:** 01c-v2 nested shelves needed each game to appear in
  exactly one genre sub-shelf; the multi-genre IGDB shape made the join
  ambiguous. Architect-deferred during 01c-v2 ("no new migrations" guard);
  shipped the same day under the "six bundled `/games` follow-ups" pass.
- **Plan link:** ties into `01c — Genres and Collections shelves`; the v1
  checkbox list assumed multi-genre fan-out and did not specify the column.
- **Driver:** `2026-05-11 — six bundled /games follow-ups` log entry.

## 2026-05-11 — Xbox added as canonical platform

- **Item:** Xbox row added to `db/seeds.rb`; `Platform::CANONICAL_SHORT_NAMES`
  + `IGDB_ID_TO_CANONICAL_SLUG` extended (49 + 169 → `xbox`).
- **Rationale:** Game show page rendered verbose IGDB names
  (`Xbox One`, `Xbox Series X|S`); user direction was to collapse to a
  single `Xbox` chip family alongside PS5 / Switch2 / Steam / GoG / Epic.
- **Plan link:** outside `plan.md`'s 5-platform seed list under `01a` —
  Phase 27 plan seeded PS5/Switch 2/Steam/GoG/Epic only.
- **Driver:** `2026-05-11 — game show page: canonical platform short names
  + Xbox seed` log entry. Later DROPPED — see `dropped.md`.

## 2026-05-15 — primary-genre column reaffirmed as IGDB-sourced

- **Item:** `Igdb::SyncGame` extended with `re_assign_primary_genre(game)`
  step; `Game#assign_primary_genre_if_blank` callback documented as
  non-sync-path safety net; `GameDecorator#as_detail_json` flipped
  `genres: [...]` → `genre: "<name>"` singular wire shape.
- **Rationale:** v2 spec 01 "single main genre per Game" collapsed the
  multi-genre model to one pin per game. The original Phase 27 plan
  carried multi-genre rendering throughout.
- **Plan link:** none — entirely a v2-spec addition layered on top of the
  original 01c shelves work.
- **Driver:** `[skipci] 2026-05-17 — v2 spec 01 Single main genre per
  Game` log entry.

## Composites / cover art

## 2026-05-11 — Collections composite cover-art pipeline (01h)

- **Item:** `Collections::ComposteLayout` + `Collections::CoverComposer` +
  `CollectionCoverRebuildJob` + `Compositable` concern (shared with
  `Bundle`) + `db/migrate/.._add_composite_cover_columns_to_collections.rb`
  + `_collection_sub_shelf.html.erb` partial. 6-variant layout matrix
  (empty / passthrough / pair / netflix3 / quad / netflix5 / six_grid) at
  98 × 130.
- **Rationale:** Plan did not specify any composite cover-art surface for
  collections. Surface introduced after 01c-v1 landed flat tiles; user
  asked for Netflix-style composite tiles.
- **Plan link:** outside the original `01c` block; closest tie is
  `01c — Tile = :shelf cover variant`.
- **Driver:** `2026-05-11 — 01h Collection cover composer (re-dispatch)`
  log entry; spec `specs/01h-collections-cover-composer.md`.

## 2026-05-17 — Composite cover-art layout matrix extension (7 / 8 / 9
tiles)

- **Item:** `Collections::CompositeLayout::LAYOUTS` extended with
  `:netflix7`, `:eight_grid`, `:nine_grid`. `MAX_TILES` bumped 6 → 9. New
  `Collections::CompositeRebuildQueue` orchestrator (sequential
  alphabetical chain of Sidekiq jobs). `CollectionCoverRebuildJob`
  rewritten from eviction-only to eager rebuild + chain advance.
- **Rationale:** v2 spec 02 — collections with 7+ games rendered with
  blank slots in the 6-cap matrix. User asked for "full coverage up to 9
  tiles" plus predictable rebuild ordering.
- **Plan link:** outside the original plan; layered on top of 01h.
- **Driver:** `[skipci] 2026-05-17 — v2 spec 02 collection cover-art
  compositions` log entry.

## 2026-05-17 — Collections shelf restructure (single-row tile + modal)

- **Item:** Rewrote `_collections_shelf.html.erb` from outer-shelf of
  per-collection sub-shelves to a single row of tile-per-collection;
  click → opens `<dialog id="collections-modal">` loading
  `/collections/:id/games_pane` as a Turbo Frame; new `_collection_tile`
  + `_collections_modal` partials; new `CollectionsController#games_pane`
  member action; new `collections-modal-trigger` Stimulus controller.
- **Rationale:** User direction mid-session — "collections is just one
  row with the compound cover art. Clicking it opens a modal." Replaces
  01c-v2's per-collection sub-shelves with a denser primary surface.
- **Plan link:** rewrites `01c — Genres and Collections shelves` post-v1.
- **Driver:** `2026-05-11 — Collections shelf restructure` log entry.

## Filter row + filter semantics

## 2026-05-11 — `?filters=` query string + `Games::Filter` query object

- **Item:** New `Games::Filter` (`app/queries/games/filter.rb`),
  `Games::FiltersHelper`, `FilterRowComponent` + `FilterChipComponent`,
  ten canonical chips, `[clear all]` link, contradiction notice for
  `owned + not_owned`. Six new `Game` scopes (`recorded`, `released`,
  `scheduled`, `on_platform`, `released_on`, `scheduled_on`).
- **Rationale:** This IS the 01b checkbox set — listing here for the
  audit trail because every downstream filter-related addition layered on
  top of these primitives.
- **Plan link:** `01b — Filter row + platform semantics` (every checkbox
  ticked).
- **Driver:** `[skipci] 2026-05-11 — sub-spec 01b Filter row + platform
  semantics` log entry.

## 2026-05-17 — Filter semantics rewrite (4-axis cascade) + ADR 0013

- **Item:** New ADR `docs/decisions/0013-games-filter-semantics.md`
  codifying four orthogonal axes (lifecycle / ownership / engagement /
  platform), within-axis OR + cross-axis AND, conditional cascade with
  mutex (e.g. `wishlist ⊥ played` only when `owned` absent), per-platform
  binding (`owned + ps5` ≡ owned-on-PS5), bidirectional auto-cascade UI.
- **Rationale:** User observed
  `?filters=released,scheduled,owned,wishlist,switch2` returning zero
  games when five Switch-family games were expected. The 01b semantics
  could not express the user's mental model.
- **Plan link:** rewrites `01b`'s "Platform-precedence combinator" (P-1 /
  P-2 / C-1 / C-3) entirely.
- **Driver:** `2026-05-17 round 7 — filter semantics rewrite locked`
  notes in the wave A–D log entry.

## 2026-05-17 — Platform chip family-collapse (ADR 0014)

- **Item:** New ADR
  `docs/decisions/0014-platform-chip-generation-collapse.md`. Chip slugs
  renamed `ps5 → ps`, `switch2 → switch`; `Platform::IGDB_ID_TO_CANONICAL_SLUG`
  maps PS4 (IGDB 48) → `ps`, Switch gen 1 (IGDB 130) → `switch`;
  `KNOWN_LOGOS` shrinks to `%w[ps switch steam]`.
- **Rationale:** User clarified intent — current-gen chip absorbs the
  family's back-catalog generations. Round 9 expanded to 5 chips, round
  10 collapsed back to 3, round 11 renamed slugs to family tokens.
- **Plan link:** rewrites `01a — Seed: ensure PS5, Switch 2, Steam, GoG,
  Epic exist by slug at boot` (drops GoG / Epic as chip-family rows; see
  `dropped.md`).
- **Driver:** Rounds 9–11 in the wave A–D log entry.

## 2026-05-17 — `games.played_platform_id` FK (implied)

- **Item:** ADR 0013 specifies a new `games.played_platform_id` FK so
  the engagement axis can bind per-platform (`played + switch` ≡ played
  on Switch). Implementation deferred.
- **Rationale:** Per-platform played binding could not be expressed under
  the original schema.
- **Plan link:** outside plan; layered on top of 01a's per-platform
  ownership table.
- **Driver:** ADR 0013 (round 7 notes).

## Per-tile chrome

## 2026-05-17 — Platform chips replace platform-logo PNG pipeline

- **Item:** New `Platforms::ChipComponent` (`:sm` + `:md` sizes) renders
  text chips in locked brand colors (PS `#003791`, Switch `#E60012`,
  Steam `#00ADEE`). Status-badge family — filled background, contrasting
  white text, NO literal `[ ]` brackets in rendered DOM. Tile-overlay
  placement: bottom-right corner of cover, background matches
  `var(--color-cover-border)`.
- **Rationale:** User direction 2026-05-17 — drop the PNG pipeline,
  switch to text chips with single color set for both themes.
- **Plan link:** replaces the v2 spec 07 platform-logos work; see
  `dropped.md`.
- **Driver:** Wave B in `2026-05-17 — waves A + B + C + D` log entry;
  user memory `project_platform_logos_to_text_chips`.

## 2026-05-17 — `Games::RatingHeatBarComponent`

- **Item:** New 200 × 14 px rating heat bar component using vote-weighted
  average score formula; tier color via `--color-rating-<tier>` tokens
  (auto-themes); the ONE allowed non-destructive use of red on the
  project (`--color-rating-bad`).
- **Rationale:** Wave C game detail revamp asked for a denser at-a-glance
  rating affordance than the prior `<NN>/100` text.
- **Plan link:** outside plan; new visual primitive for `/games/:id`.
- **Driver:** Wave C5 in the wave A–D log entry; design.md addition.

## 2026-05-17 — Genre short-name mapping rewrite (`GenresHelper::SHORT_NAMES`)

- **Item:** New `SHORT_NAMES` table mapping IGDB genre names to short
  labels (RPG, JRPG, FPS, MOBA, RTS, TBS, Sim, Hack/Slash, VN, etc.).
  Both `Shooter` and `First-person Shooter` collapse to `FPS`. Unknown
  genres fall through to IGDB canonical name unchanged.
- **Rationale:** v2 spec 05 — shelf headings needed a denser vocabulary
  than IGDB's full names.
- **Plan link:** outside plan; layered on top of 01c shelves.
- **Driver:** `[skipci] 2026-05-17 — v2 spec 05 Games index shelves-only`
  log entry.

## 2026-05-17 — `StatusTbdBadgeComponent` + `SearchPlaceholderModalComponent`

- **Item:** Two new placeholder components — orange `[TBD]` badge for
  unfinished surfaces; modal that renders the TBD badge + "search coming
  soon" copy for `/` keypress.
- **Rationale:** Wave C/D needed visible placeholders for footage +
  global search surfaces that aren't built yet.
- **Plan link:** outside plan; placeholders for future work.
- **Driver:** Wave C11 + D5 in the wave A–D log entry.

## Sync + live UI

## 2026-05-17 — `GameIgdbSync` live broadcast + sync banner

- **Item:** `GameIgdbSync` job hardened: Sidekiq uniqueness lock
  (intent-only on Sidekiq OSS), explicit
  `Collections::CompositeRebuildQueue#enqueue_for_game_resync(game)` on
  success, Turbo-Stream broadcast on `"game_resync:<id>"` swapping the
  `games/_sync_status` partial; `app/views/games/show.html.erb` added
  `turbo_stream_from "game_resync:#{@game.id}"` permanent subscription.
- **Rationale:** v2 spec 03 — user asked for live "synced ~22m ago"
  banner that updates without page refresh, plus a `[resync]` button
  that swaps to a dot-loader during the in-flight sync.
- **Plan link:** outside plan; sync surface was not in the original 01*
  spec set.
- **Driver:** `[skipci] 2026-05-17 — v2 spec 03 Game resync job` log
  entry.

## IGDB add-game flow

## 2026-05-17 — IGDB add-game modal polish + legacy-create removal

- **Item:** `_igdb_search_modal.html.erb` trimmed copy + dropped explicit
  `[search]` button (auto-search at 5-char threshold, Enter override);
  `[cancel]` swapped to `BracketedMutedLinkComponent`; new
  `.pane-dialog--wide` modifier. `GamesController#create` REMOVED the
  legacy `Game.new + save!` fallthrough — IGDB is now the sole entry
  point to create a game. Title pre-seeded from the IGDB result row so
  the breadcrumb reads the canonical title during the in-flight sync.
- **Rationale:** v2 spec 04 — the legacy "Untitled game" row leaked into
  the UI; IGDB add-game was already the only used entry point.
- **Plan link:** outside plan; surface didn't exist as a checkbox.
- **Driver:** `[skipci] 2026-05-17 — v2 spec 04 IGDB add-game modal
  polish` log entry.

## Keybindings

## 2026-05-17 — `page_actions:` YAML + leader-menu restructure

- **Item:** New top-level `page_actions:` key in
  `config/keybindings.yml`; new
  `KeybindingsReferenceComponent`; new keyboard-controller hooks
  (`page_sync`, `page_delete`, `page_add_bundle`). Bulk leader rows
  dropped (`menus.games.items` lost `[- bulk_delete]` + `[r bulk_resync]`).
  Leader popup restructured 2026-05-18: `actions` → `local`,
  `navigation` → `global`; 2-column grid layout for filter chips +
  create-row; root menu trimmed to `Gl games` + `S settings` + `q quit` +
  `Q logout`; new `G+ add game` + `Gb add bundle` page-actions.
- **Rationale:** v2 spec 09 — keyboard discovery affordance for
  per-page actions (sync, delete, search) that don't belong in the
  global navigation menu. 2026-05-18 restructure reflects user direction
  to collapse the leader popup.
- **Plan link:** outside plan; keybinding surface was not in original
  Phase 27 scope.
- **Driver:** Wave D in wave A–D log entry; 2026-05-18 leader menu
  restructure log entry.

## Game detail page (Wave C revamp)

## 2026-05-17 — `/games/:id` show rebuilt around new layout

- **Item:** Routes lost `resources :games`'s `:edit` + `:update` (game
  edit page retired — see `dropped.md`). LEFT pane: title → genres
  (primary bold + up to 2 alphabetical secondaries) → meta line → rating
  heat bar → ownership row (platform chips toggle ownership via
  `PlatformOwnershipsController#update`; single `[played]` and
  `[recorded]` chips; `[TBD]` footage) → sync banner. RIGHT pane: only
  summary + time-to-beat (3-column main / extras / completionist with
  `ttb_hours(seconds)` helper, em-dash for nil). Breadcrumb gained
  `[resync]` (POST) + `[delete]` (opens existing `ConfirmModalComponent`).
- **Rationale:** Wave C end-to-end rebuild around the user's new layout
  direction. Stripped: stores section, ratings table, detail time-to-beat
  table, local-fields table, RIGHT-pane platforms heading + chip row.
- **Plan link:** rewrites the `01f` surface and removes the
  `Game#edit` page entirely.
- **Driver:** Wave C slices C1–C11 in the wave A–D log entry.

## Bundles (formerly "Collections") consolidation

## 2026-05-17 — Collections → Bundles rename (Wave A consolidation)

- **Item:** `collections` table dropped; `games.collection_id` column
  dropped; `Game`, `Bundle`, `GameIgdbSync` repointed at
  `Bundles::CompositeRebuildQueue` instead of `Collections::*`.
- **Rationale:** User direction to consolidate around `Bundle` as the
  canonical user-defined-group model; `Collection` was redundant.
  Discovery: working tree was already at the desired end-state by the
  Wave A dispatch; verification + smoke test only.
- **Plan link:** rewrites every `01c`/`01h` reference to "collections"
  shelves. Original plan said "Collections shelf"; new vocabulary is
  "bundle shelf".
- **Driver:** Wave A in wave A–D log entry; user memory
  `project_bundle_consolidation_followup`.

## Omnisearch (2026-05-19 slice A1)

## 2026-05-19 — `games.alternative_names text[]` column + GIN index

- **Item:** New `games.alternative_names text[]` column,
  `default: []`, `null: false`, plus
  `index_games_on_alternative_names` GIN index.
  `Igdb::Client::GAME_FIELDS` extended with
  `alternative_names.id` + `alternative_names.name`;
  `Igdb::GameMapper.extract_alternative_names` populates the column
  on every sync (deduplicated, blanks dropped; resets to `[]` when
  IGDB omits the field). `Meilisearch::GameIndexer` adds
  `alternative_names` to `SEARCHABLE_ATTRIBUTES` immediately after
  `title` so the field outranks `summary` / dev / pub / genre.
- **Rationale:** User filed the bug "typing SF6 should find Street
  Fighter 6". Two options were on the table — federate alt-name
  lookup to IGDB per-keystroke (Option B) or persist alt names
  locally and search them like any other column (Option A). Option A
  landed: no per-keystroke IGDB round-trip, Meilisearch handles the
  weighting, Postgres ILIKE fallback covers stale-index cases. The
  empty-array invariant makes the `EXISTS (SELECT 1 FROM
  unnest(alternative_names) ...)` predicate safe to run
  unconditionally.
- **Plan link:** outside plan; new schema column not present in any
  Phase 27 plan or v2 spec. Closest tie is the `/games` omnisearch
  surface (post-Wave-D follow-up).
- **Driver:** 2026-05-19 chat — search-quality pass; log entry
  `[skipci] 2026-05-19 — omnisearch alt-names + always-search-both
  + dedup (pito-rails, slice A1)`.

## 2026-05-19 — always-search-both omnisearch dispatch contract

- **Item:** `Games::SearchService` now calls `call_igdb(query)` on
  EVERY dispatch (both `:bundle_add` and `:games_search` modes), not
  just when the local pane is empty. The previous "lazy IGDB" mode
  skipped the remote call when the local half had hits.
- **Rationale:** User direction — the local row may be an alt-edition,
  a stale title, or a community import; the user needs the
  IGDB-canonical row alongside it for comparison. With the new
  dedup-by-`igdb_id` rule absorbing the duplicate-row case (next
  entry), always-search-both adds at most one IGDB round-trip per
  dispatch and gives the omnisearch modal its canonical-vs-import
  comparison affordance.
- **Plan link:** outside plan; dispatch contract not in any Phase 27
  plan or v2 spec.
- **Driver:** 2026-05-19 chat — search-quality pass; log entry as
  above. Cross-referenced from
  `docs/architecture.md > Games omnisearch`.

## 2026-05-19 — dedup-by-`igdb_id` post-filter

- **Item:** `Games::SearchService` Rule 1 promoted from "applies only
  in `:game_index` mode" to "applies in every mode that returns
  IGDB rows". The dispatcher filters out any IGDB row whose `id`
  matches any `igdb_id` on a local Game in the same response. The
  local row wins.
- **Rationale:** UX rule — the user should see any given game in
  exactly ONE omnisearch section, never two. Pairs with the
  always-search-both contract: without dedup, the IGDB section would
  re-list every row the user already imported. With dedup, the
  three-section model (games / bundles / on IGDB) stays coherent.
- **Plan link:** outside plan; UX rule not previously documented.
  Now lives in `docs/design.md > Omnisearch modal`.
- **Driver:** 2026-05-19 chat — search-quality pass; log entry as
  above.
