# Beta-3 Lane B — ViewComponent extraction candidates

Audited: 2026-05-18 (read-only sweep over `app/views/games/`,
`app/views/settings/`, `app/views/bundles/`, and the `app/views/shared/`
partials those areas exclusively own).

Criteria (locked by user, NOT reusability):

1. Complexity — conditional branches, multiple slots / state variants,
   embedded computation, or > 30 lines of ERB.
2. Test-isolation need — markup that encodes business rules a unit spec
   ought to lock down independently of a full view render.

A simple repeating element used in 5 places but trivially small is NOT
a candidate. A complex 60-line ERB used only ONCE IS a candidate.

Already-extracted components (verified — see `app/components/games/`,
`app/components/bundles/`, `app/components/platforms/`,
`app/components/`) are skipped. Notes:

- `Games::SyncBannerComponent` does NOT exist on disk. The "sync banner"
  on the left pane of /games/:id was removed in the Wave C8 polish; the
  breadcrumb `[sync]` is the only sync surface. Nothing to extract or
  rename — flagged here so the next sweep doesn't keep looking.
- `Bundles::CoverCompositeComponent` does NOT exist on disk. The
  composite cover for bundles still renders through the
  `shared/_composite_cover` partial (simple `<img>` + fallback span) AND
  through the inline CSS-grid composite inside
  `app/views/bundles/games_pane.html.erb` (the bundles-modal cell grid
  that mirrors `Composite::CellMap`). The modal composite IS a clear
  winner below (B5); the small `shared/_composite_cover` partial is
  too thin to warrant extraction.

## Clear winners — Phase 2 implements autonomously

### B1. Games::DetailCoverComponent

- Current location: `app/views/games/show.html.erb:121-150` (~30 lines
  of inline ERB, including the platform-chip slug computation block).
- Proposed component:
  `Games::DetailCoverComponent` at
  `app/components/games/detail_cover_component.{rb,erb}`.
- Complexity signal:
  - Inline `PlatformLogosHelper::KNOWN_LOGOS.select` walk that combines
    `game_detail_logo_slugs(@game)` with
    `Array(game_index_tile_logo_slug(@game))`.
  - Conditional overlay branch (only when `detail_chip_slugs.any?`).
  - Layered render (wrapper + shared `_igdb_cover` partial + chip
    overlay strip with per-chip `Platforms::ChipComponent` loop).
- Test-isolation need:
  - Encodes the "which platform chips light up on the detail surface"
    decision — currently lives in a view template, hostile to a focused
    spec. A `render_inline(Games::DetailCoverComponent.new(game: g))`
    spec can lock down slug computation against fixture games without a
    full /games/:id request render.
- Estimated wall-clock for Phase 2 impl + initial spec stubs: ~12 min.
- Notes: User explicitly named this as the live-update target for the
  ownership-toggle Turbo Stream flow (the breadcrumb `[+ platform]` /
  ownership editor will broadcast a replace of `#game_detail_cover_<id>`
  on save). The component should expose a stable DOM id
  (`id: "game_detail_cover_#{game.id}"`) on the outer wrapper so the
  Turbo Stream target is one piece. Keep `shared/_igdb_cover` untouched
  (other callers).

### B2. Games::GenresLineComponent

- Current location: `app/views/games/show.html.erb:164-187` (~24 lines
  of ERB inside a single `<div class="game-genres">` block).
- Proposed component:
  `Games::GenresLineComponent` at
  `app/components/games/genres_line_component.{rb,erb}`.
- Complexity signal:
  - Computes `primary`, `secondaries` (with explicit `.where.not(id:)`
    +`order(:name)` + `limit(2)` query inside the view), then composes
    `genres_list = ([primary] + secondaries.to_a).compact`.
  - Two conditional render paths (genres-present iteration with
    primary-vs-secondary `<strong>` switch + separator dot interleave;
    empty `<em>—</em>` fallback).
  - Calls into `GenresHelper#genre_display_name` (renames table).
- Test-isolation need:
  - Encodes "primary + up to 2 secondaries, alphabetical, primary in
    bold, em-dash when none" — a business rule that ought to be locked
    down separately from /games/:id. Easy to spec with build_stubbed
    games + a fake `Genre` set.
- Estimated wall-clock: ~8 min.
- Notes: The component should keep using `GenresHelper#genre_display_name`
  (already a helper). Pulling the query into a `secondaries_for(game)`
  class method or memoized instance method keeps the view simple.

### B3. Games::MetaTableComponent

- Current location: `app/views/games/show.html.erb:204-250` (~46 lines
  including the `meta_rows = []` builder, the `release_date` /
  `developers` / `publishers` / `sync` rows, and the `<table class=
  "kv-table">` markup).
- Proposed component:
  `Games::MetaTableComponent` at
  `app/components/games/meta_table_component.{rb,erb}`.
- Complexity signal:
  - Builder block that pushes rows conditionally (release_date present,
    developers.any?, publishers.any?, always sync).
  - Per-row `resyncing?` branch on the sync value (`"---"` vs
    `compact_time_ago(igdb_synced_at)`).
  - Date format `"%m-%d-%Y"`, `compact_time_ago` for ago strings,
    `title=` truncation attribute pattern.
- Test-isolation need:
  - Captures the "which rows render, in what order, with what format"
    decision — exactly the kind of business rule a unit spec on the
    component pins down (and the kind that has been subtly tweaked
    multiple times per the dated comments).
- Estimated wall-clock: ~10 min.
- Notes: Inputs are `game:` only. The component itself can call
  `compact_time_ago` (helper) by including `Rails.application.routes
  .url_helpers` is unnecessary; ViewComponent inherits
  `ApplicationHelper`. Keep `kv-table` markup verbatim.

### B4. Games::BundlesSectionComponent

- Current location: `app/views/games/show.html.erb:337-385` (~48 lines
  including `bundles_in` + `bundles_suggested` queries + dual-shelf
  layout + the divider conditional + empty-state tile).
- Proposed component:
  `Games::BundlesSectionComponent` at
  `app/components/games/bundles_section_component.{rb,erb}`.
- Complexity signal:
  - Two upstream queries (`@game.bundles.order(Arel.sql...)` +
    `Bundles::SuggestedFor.call(@game, limit: 3)`) with subtraction
    (`bundles_suggested - bundles_in`).
  - Three render branches (both-empty empty-tile; LEFT-only; RIGHT-only;
    both-present with divider).
  - Calls `Games::BundleTileComponent` in two distinct modes
    (default + `mode: :suggest, target_game: @game`).
- Test-isolation need:
  - The "subtract member bundles from suggested" rule is silent-
    failure-prone; pinning it in a component spec catches a regression
    where a bundle the game already belongs to leaks into the
    recommendation row.
- Estimated wall-clock: ~10 min.
- Notes: Bundles modal partial + per-bundle confirm-delete dialog
  rendering should STAY at the page level (the show template renders
  them as siblings explicitly so the `<dialog>` doesn't nest inside
  interactive content). The new component owns ONLY the
  `<section class="game-bundles">` block.

### B5. Bundles::ModalCompositeComponent

- Current location: `app/views/bundles/games_pane.html.erb:37-84`
  (~47 lines — the CSS-positioned composite that mirrors libvips,
  cell loop using `Composite::CellMap.for(first_nine.size)`,
  per-cell anchor render, master-URL fallback to IGDB).
- Proposed component:
  `Bundles::ModalCompositeComponent` at
  `app/components/bundles/modal_composite_component.{rb,erb}`.
- Complexity signal:
  - Pulls `games.first(9)` + `Composite::CellMap.for(n)` (already-
    extracted service — perfect; the component just consumes it).
  - Percentage-positioned absolute layout (each cell's `left/top/w/h`
    computed inline as `cell[:x] * 100`).
  - Per-cell cover-master URL with fallback (`game.cover_master_url
    (fallback_size: "t_cover_big_2x")`).
  - Mirror of the libvips renderer — the two surfaces must stay in
    sync. A component spec on the CSS composite (asserting that the
    rendered cell `left/top/width/height` percentages match
    `Composite::CellMap.for(n)` outputs) is the natural place to lock
    that invariant.
- Test-isolation need:
  - HIGH. The pairing with `Composite::CellMap` (already a unit-tested
    service) is the exact "encodes business rule, render-isolatable"
    case the criteria call out.
- Estimated wall-clock: ~12 min.
- Notes: The empty-bundle netflix3 placeholder block immediately below
  (lines 85-128 in `games_pane.html.erb`) is a separate concern — see
  B6.

### B6. Bundles::EmptyCoverPlaceholderComponent

- Current location: `app/views/bundles/games_pane.html.erb:85-128`
  (~43 lines of netflix3 placeholder markup — three controller-icon
  cells with theme-aware light/dark image pairs).
- Proposed component:
  `Bundles::EmptyCoverPlaceholderComponent` at
  `app/components/bundles/empty_cover_placeholder_component.{rb,erb}`.
- Complexity signal:
  - 6 `image_tag` calls (3 cells × 2 themes) with repetitive class
    strings and `data-theme` switching.
  - Mirrors the shelf-tile no-cover treatment with a `--modal` modifier
    — the markup MUST stay in step with the shelf-tile version, and
    today there is no enforced invariant.
- Test-isolation need:
  - Medium-high. The "controller-icon netflix3 placeholder" pattern is
    duplicated in `Games::BundleTileComponent`'s no-cover fallback;
    pulling it into a shared component would deduplicate AND give us a
    spec that pins the theme-pair markup.
- Estimated wall-clock: ~8 min.
- Notes: The component should accept an optional `modifier:` (e.g.
  `:modal` vs default) so the shelf-tile no-cover fallback can
  eventually share the same primitive without forcing the Phase 2 work
  to also refactor `Games::BundleTileComponent`. Step 1: extract;
  step 2 (later): swap `Games::BundleTileComponent`'s inline copy to
  render the new component.

### B7. Sessions::TableComponent

- Current location: `app/views/settings/_security_pane.html.erb:39-105`
  (~67 lines — the sortable sessions table with toolbar +
  bulk-revoke checkboxes + IP tooltip + this-session badge + the
  pane-level confirm modal at lines 134-174).
- Proposed component:
  `Sessions::TableComponent` at
  `app/components/sessions/table_component.{rb,erb}`.
- Complexity signal:
  - Bulk-toolbar `[revoke]` muted/active state hook + checkbox loop
    with per-row `data-current="yes/no"` flag.
  - `sort_link_to(...)` for two columns with shared sort/dir params.
  - Per-row inline composition of `<code>` + `TooltipBadgeComponent`
    + conditional `StatusBadgeComponent("this")`.
  - Empty-state branch ("no active sessions.").
- Test-isolation need:
  - The "current session = `[this]` badge after IP tooltip" decision is
    a business rule (which row is currently authenticated and how to
    signal it) that ought to be testable separately from the full
    /settings render. Same for "bulk-revoke disabled until at least one
    checkbox ticked" — that lives in the Stimulus controller AND the
    initial render; the initial render IS the component's
    responsibility.
- Estimated wall-clock: ~14 min.
- Notes: The page-level `<dialog id="revoke_sessions_modal">` block
  (lines 134-174) is a SEPARATE concern — see B8. Component takes
  `sessions:`, `sessions_sort:`, `sessions_dir:`. It does NOT own the
  `data-controller="sessions-bulk-revoke"` mount — that wraps both the
  table and the dialog, so it stays on the parent fieldset in
  `_security_pane.html.erb`.

### B8. Sessions::BulkRevokeModalComponent

- Current location: `app/views/settings/_security_pane.html.erb:134-175`
  (~41 lines — the `<dialog id="revoke_sessions_modal">` with title
  target, warning target, form target with CSRF refresh action, and
  the `[revoke]`/`[cancel]` actions).
- Proposed component:
  `Sessions::BulkRevokeModalComponent` at
  `app/components/sessions/bulk_revoke_modal_component.{rb,erb}`.
- Complexity signal:
  - Carries multiple Stimulus targets the
    `sessions-bulk-revoke` controller writes into at click time
    (`modal`, `modalTitle`, `modalWarning`, `modalForm`).
  - Wires a literal `0` ids placeholder URL the controller rewrites
    on open + a CSRF refresh hook on submit.
  - `confirm-modal` controller actions for Esc / outside-click
    handling.
- Test-isolation need:
  - Asserting that the placeholder URL is `0` (not `1`, not blank — the
    route constraint requires a digit, `0` is filtered server-side) is
    exactly the kind of integration-fragile detail a component spec
    pins down.
- Estimated wall-clock: ~8 min.
- Notes: Does NOT replace `ConfirmModalComponent` — the bulk-revoke
  dialog has a unique requirement (dynamic title + dynamic warning +
  dynamic form action from Stimulus) that the generic
  `ConfirmModalComponent` doesn't support. Keep both.

### B9. Settings::Stack::Sidekiq::CountersComponent

- Current location: `app/views/settings/_stack_pane.html.erb:101-193`
  (~93 lines including the `sidekiq_counts` hash builder AND the two
  spacer-aligned tables — the 2-col lifetime grid and the 5-col queue
  grid, both with `table-layout: fixed` 5-column shared grid).
- Proposed component:
  `Settings::Stack::Sidekiq::CountersComponent` at
  `app/components/settings/stack/sidekiq/counters_component.{rb,erb}`.
- Complexity signal:
  - The "two semantic groupings as two tables sharing one 5-col grid
    so lifetime values align with queue values below" is encoded
    entirely in markup (colgroups + empty spacer cells).
  - Per-state cell wrapping with `data-stack-stats-live-target` for the
    polling controller, hooked off five hard-coded queue states.
  - Counts hash built inline from `@sidekiq_breakdown`.
- Test-isolation need:
  - The alignment invariant (`successful` lands under `enqueued`,
    `failed` under `dead`) is silent-failure-prone — a layout
    refactor that drops a spacer column breaks the visual without any
    spec catching it. A `have_css('th.num', count: 5)` /
    `have_css('td.num[data-stack-stats-live-target="successful"]')`
    spec locks it down.
- Estimated wall-clock: ~10 min.
- Notes: Component accepts `breakdown:` (Array of `{label:, count:}`)
  and computes the hash internally. Stimulus targets stay verbatim.

### B10. Settings::Stack::HealthLineComponent

- Current location: Repeated 6 times across
  `app/views/settings/_stack_pane.html.erb` (Postgres / Redis /
  Meilisearch / assets / notes — lines 43-50, 92-99, 200-207, 298-309,
  352-363) AND in `app/views/settings/_voyage_section.html.erb:69-76`
  for Voyage.
- Proposed component:
  `Settings::Stack::HealthLineComponent` at
  `app/components/settings/stack/health_line_component.{rb,erb}`.
- Complexity signal:
  - Each instance is a 7-9-line div with the same `<span><strong>{name}
    </strong></span>` + tri-state status branch
    (connected/configured/writable vs disconnected/not-configured/
    read-only vs absent).
  - The "tri-state" decision is encoded slightly differently per
    consumer (Postgres/Redis use `:connected`; assets/notes use
    `:present` + nested `:writable`; Voyage uses
    `AppSetting.voyage_configured?` plus implicit "configured" copy).
- Test-isolation need:
  - The "▲ / ▽" glyph + class mapping is duplicated 7 times with
    subtle copy differences. A single component with a `state:`
    enum (`:connected`, `:disconnected`, `:writable`, `:read_only`,
    `:absent`, `:configured`, `:not_configured`) + `label:` arg lets
    one spec lock the mapping down once.
- Estimated wall-clock: ~10 min.
- Notes: This is a borderline-reusability case BUT the duplication is
  inside a single page (the stack pane) and the tri-state decision
  encodes a presentational invariant. The component lets the Phase 2
  refactor of _stack_pane.html.erb shrink by ~30 lines, AND replacing
  the duplicated copy with a typed `state:` enum is a clarity win.
  Per the criteria, "test-isolation need" carries this one across
  the line.

### B11. Settings::TotpEnrollmentPaneComponent

- Current location: `app/views/settings/security/totps/new.html.erb`
  (~120 lines total; the QR pane block lives at lines 64-106 — ~43
  lines including the `RQRCode::QRCode.new(@totp_uri)` SVG render +
  white-bg wrapper + seed `<pre>` + enter-code form).
- Proposed component:
  `Settings::TotpEnrollmentPaneComponent` at
  `app/components/settings/totp_enrollment_pane_component.{rb,erb}`.
- Complexity signal:
  - Inline `RQRCode::QRCode.new(@totp_uri).as_svg(...)` call followed
    by `html_safe` — exactly the kind of embedded computation that
    deserves a memoized component method.
  - White-on-dark theme caveat baked into the wrapper styles.
  - Enter-code form is a critical-path 2FA enrollment input; isolating
    it from the surrounding modal turbo-frame wrapper makes the form
    spec-friendly.
- Test-isolation need:
  - The QR SVG block has caused at least one polish revision (white-bg
    wrapper for dark mode contrast). A component spec
    `render_inline(Settings::TotpEnrollmentPaneComponent.new(totp_uri:
    ..., seed: ...))` can assert the SVG container carries
    `background: #ffffff` AND `display: inline-block` so the
    contrast-fix invariant doesn't silently regress.
- Estimated wall-clock: ~10 min.
- Notes: Component takes `totp_uri:`, `seed:`. The right-pane backup
  codes block (lines 108-117 of the same file) is simpler (~10 lines)
  and not worth a separate extraction — leave inline.

## Debatable — user reviews on return

### B12. Settings::WebhookPaneComponent (Slack + Discord)

- Current location: `app/views/settings/_slack_pane.html.erb` (~113
  lines) + `app/views/settings/_discord_pane.html.erb` (~118 lines).
- Why debatable:
  - The two panes are NEAR-IDENTICAL — same form structure, same
    `[update]` + `[help]` actions, same two auto-save checkbox rows,
    differing only in the brand name, the controller URL helper, the
    placeholder mask helper, and the `data-leader-toggle` slug. The
    criteria explicitly says "NOT based on reusability" — but the
    duplication ALSO encodes a per-brand business rule (which routing
    flags exist for that brand) that is hostile to a spec across both.
  - The complexity per pane is modest (one form + two checkbox forms,
    each ~10 lines).
- Agent's proposed verdict: EXTRACT into a single shared
  `Settings::WebhookPaneComponent` taking `brand:` (`:slack` /
  `:discord`), `webhook:` (the SlackWebhook / DiscordWebhook record).
  The two view files become 3-line callers.
- Rationale: The "every shared concern between Slack & Discord" surface
  is precisely the operator surface most likely to drift between
  brands (a fix lands on one pane, lands later on the other). The fact
  that the only differences are 4 named values means the per-brand
  spec can assert exactly those 4 are correctly wired without
  duplicating the surrounding form-structure spec. Borderline because
  the criteria de-prioritize reusability — but the test-isolation win
  carries it.

### B13. Settings::Stack::PaneComponent (the whole stack pane)

- Current location: `app/views/settings/_stack_pane.html.erb` (~398
  lines — the entire wide pane with db / search / storage / notes
  columns).
- Why debatable:
  - The pane is large (~398 lines) but already structured as 4
    sub-sections separated by `<hr class="hairline">`. Extracting it
    wholesale into one component doesn't actually reduce complexity —
    it just relocates 398 lines.
  - The bigger win comes from extracting the SIX sub-tables (Postgres,
    Redis-sidekiq-counters [B9], Meilisearch, Voyage [already a
    partial], assets, notes) as discrete sub-components. The pane
    itself stays as a thin orchestrator.
- Agent's proposed verdict: LEAVE INLINE as the orchestrator; extract
  the high-value sub-components (B9 above + possibly
  `Settings::Stack::PostgresTableComponent`,
  `Settings::Stack::MeilisearchTableComponent`,
  `Settings::Stack::AssetsTableComponent`,
  `Settings::Stack::NotesTableComponent` as a follow-up).
- Rationale: The four `data-controller="sortable-table"`-wrapped
  3-column tables (postgres / meilisearch / assets / notes) are
  STRUCTURALLY VERY SIMILAR (label / number / size; live-stats
  targets; sortable headers). Per criteria they're ~40-line blocks
  each with conditional cells (e.g. Meilisearch `omit_size`,
  `missing`) — possibly extractable into ONE shared
  `Settings::Stack::SortableSizeTableComponent` taking
  `rows:`, `id:`, `label_col_header:`. That's a bigger refactor
  Phase 2 should not autonomously decide.

### B14. Games::BundlesModalComponent

- Current location: `app/views/games/_bundles_modal.html.erb` (~135
  lines — the layout-positioned `<dialog id="bundles-modal">` with
  inline title edit, per-bundle delete confirm trigger, turbo frame).
- Why debatable:
  - Already-extracted ConfirmModalComponent + the
    `bundles-modal-trigger` Stimulus controller carry most of the
    behavioral logic. The ERB itself is wiring (Stimulus targets +
    optional `bundle:` local pre-population).
  - Complexity is real (3 Stimulus controllers, dual display/editing
    rows for the title, an autoopen mode for the create flow) but the
    spec value of isolating it is lower than the components above —
    the page-level spec already exercises this dialog via the trigger
    + the turbo-stream create response.
- Agent's proposed verdict: LEAVE INLINE for now; revisit if the modal
  grows another mode.
- Rationale: The dialog's behavior is driven primarily by the Stimulus
  controllers (`bundles-modal-trigger`, `bundles-modal-reset`,
  `inline-title-edit`, `modal-trigger`, `confirm-modal`,
  optional `bundles-modal-autoopen`). Pulling the ERB into a
  component without also restructuring the Stimulus coupling buys us
  little. The component would basically be a render shim with one
  conditional (`bundle:` local present vs absent).

### B15. Games::OmnisearchResultsComponent (combined)

- Current location: `app/views/games/_search_results_combined.html.erb`
  (~113 lines) AND `app/views/bundles/_search_results.html.erb` (~84
  lines).
- Why debatable:
  - Three near-identical section blocks per file (local games / local
    bundles / IGDB) with subtly different per-row affordances (`[add]`
    posts to /games for the omnisearch flow vs /bundles/:id/members
    for the bundle-add flow vs `[open]` for existing IGDB hits in the
    omnisearch flow).
  - The per-row affordance variability is the business rule worth
    isolating. The shared "section heading + hairline-between-
    sections + empty-section copy" scaffolding is the duplication.
- Agent's proposed verdict: EXTRACT a shared
  `Search::ResultsSectionComponent` (heading + hairline + empty-state
  + body slot) + leave the per-row affordance partials inline. This
  is a bigger restructure than the rest of the clear-winner list.
- Rationale: The two partials share STRUCTURE more than per-row
  behavior. A shared section primitive lets both files shrink AND
  prevents the section-separator hairline rules from drifting. But
  the win is modest (the partials work today) and the scope
  (introducing a new Search:: namespace) is bigger than the rest of
  the Phase 2 list.

### B16. Settings::SettingsModalComponent

- Current location: `app/views/settings/_settings_modal.html.erb`
  (~131 lines, but the lion's share is comment prose explaining
  layout decisions; actual markup is ~30 lines).
- Why debatable:
  - The comment density (~100 of 131 lines) inflates the apparent
    complexity. The markup itself is a single `<dialog>` with a
    fixed-shape header + turbo-frame body.
  - The two `local_assigns.fetch`-driven parameters (`auto_open_url`,
    `non_dismissible`) ARE the kind of state-variant decision the
    criteria call out — they swap the close button visibility, the
    Stimulus value attributes, and (historically) the inner max-
    width.
- Agent's proposed verdict: EXTRACT as
  `Settings::SecurityModalComponent` (or `Settings::SettingsModal
  Component`). The two named locals become typed initializer args.
- Rationale: Borderline. The actual markup is short, but the
  `non_dismissible` mandatory-2FA mode IS a state-variant business
  rule (mandatory enrollment cannot be dismissed). A focused spec
  on the component asserting "when non_dismissible: true, no `[close]`
  link, no `data-action='click->settings-modal#clickOutside'`" pins
  down a security-relevant invariant.

### B17. Games::ResyncBreadcrumbComponent

- Current location: `app/views/games/show.html.erb:36-95` (~60 lines
  inside `content_for(:breadcrumb_actions)`, including the resyncing-
  vs-active branch + the `[sync]` confirm-modal trigger + the
  `[delete]` confirm-modal trigger + the page-action `data-` hooks).
- Why debatable:
  - The two trigger anchors share a pattern (`bracketed text-danger` +
    `data-controller="modal-trigger"` + `data-page-action`) and the
    `[sync]` anchor has a resyncing-vs-active mutex branch.
  - But the markup lives inside `content_for(:breadcrumb_actions)`,
    which complicates the component story — the component would have
    to either render INTO the content_for block from inside the
    parent template (awkward) or return a string the parent yields.
- Agent's proposed verdict: LEAVE INLINE; the `content_for` wrapping
  is the awkward bit, not the markup.
- Rationale: Extracting into a component forces a `content_for`
  outside the component (still in the show template) which doesn't
  reduce the template's surface area meaningfully. Could instead
  extract just the `[sync]` mutex branch as a
  `Games::ResyncTriggerComponent` (~20 lines) and keep `[delete]`
  inline — but that's a smaller win than the items above.

### B18. Games::SimilarShelfComponent

- Current location: `app/views/games/show.html.erb:386-415` (~30
  lines — calls `Games::SimilarGames.call(@game, limit: 10)` then
  wraps the shelf row).
- Why debatable:
  - Genuinely simple — a service call + a shelf row + an empty-state
    tile. Right at the threshold.
  - The pattern (service call + shelf wrapper + empty-state) is
    identical to the bundles section above (B4) — extracting both
    together as a shared "section with shelf" primitive might be
    cleaner than two parallel components.
- Agent's proposed verdict: LEAVE INLINE for the first pass. Revisit
  if B4 lands and a shared primitive becomes obvious.
- Rationale: The criteria explicitly mark trivial "3-line div in 5
  places" as NOT a candidate; this is closer to "1 service call +
  loop + empty-state in 1 place". The complexity is in
  `Games::SimilarGames` (a service, already isolated), not in the
  view.

## Summary

- Clear winners: 11
- Debatable: 7
- Estimated total Phase 2 wall-clock for impl + initial spec stubs
  (clear winners only): ~112 min ≈ 1h 52m (B1 12m + B2 8m + B3 10m +
  B4 10m + B5 12m + B6 8m + B7 14m + B8 8m + B9 10m + B10 10m + B11
  10m).
- The clear winners cluster around `/games/:id` (B1–B4), the bundles
  modal pane (B5–B6), the security pane (B7–B8), the stack pane (B9–
  B10), and the TOTP enrollment surface (B11). Phase 2 dispatches
  should batch by area (4 dispatches: games-detail, bundles-modal,
  security-pane, stack-and-totp) so the parallel agents don't collide
  on the same template files.
