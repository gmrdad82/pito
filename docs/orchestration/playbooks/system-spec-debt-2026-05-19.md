# System spec debt — 2026-05-19

**Source:** `bin/test all` run completed 2026-05-19 (9392 examples, 35 failures,
848s). **Status:** Deferred to /channels wave (next phase). Not fixed in current
session. **Reason:** All 35 fails are SYSTEM specs (Capybara). Default
`bin/test` skips `type: system` per `.rspec`, so this debt accumulated silently
through the /games revamp + cleanup waves without surfacing in the fast loop.

System specs typically expensive to fix mid-flow; user opted to bundle the
cleanup into the next phase's consolidation pass when /channels work brings the
system-spec suite back into focus.

## Failures by file

| Count | File                                          |
| ----- | --------------------------------------------- |
| 10    | spec/system/games_index_spec.rb               |
| 6     | spec/system/settings_webhooks_spec.rb         |
| 5     | spec/system/games_platform_ownerships_spec.rb |
| 4     | spec/system/notifications_navbar_modal_spec.rb |
| 3     | spec/system/keyboard_row_navigation_spec.rb   |
| 2     | spec/system/igdb_add_game_spec.rb             |
| 1     | spec/system/password_reset_via_2fa_spec.rb    |
| 1     | spec/system/keyboard_grid_navigation_spec.rb  |
| 1     | spec/system/games_steam_shelf_spec.rb         |
| 1     | spec/seeds_spec.rb                            |
| 1     | spec/requests/settings_spec.rb                |

Total: 35.

## Clusters (root-cause grouping)

### Cluster 1 — Collection model drop ripples (3 fails) — DELETE candidate

- `keyboard_row_navigation_spec.rb:100, 106, 228` — all reference
  `let!(:collection_a) { create(:collection, name: "Alpha") }` and
  `/collections` routes. Collection model was dropped in Wave A (Phase 27
  follow-up); these specs are dead.
- **Disposition:** delete or rewrite to use Bundle if equivalent row-navigation
  coverage is needed.

### Cluster 2 — Notifications navbar mute cascade (4 fails) — REWRITE

- `notifications_navbar_modal_spec.rb:46, 52, 58, 64` — all assert the navbar
  `[notifications]` link has a
  `data-action="...notifications-modal#open"` Stimulus action. The navbar-mute
  dispatch (2026-05-19) converted `[notifications]` to a non-clickable muted
  span — the modal-open contract is gone.
- **Disposition:** delete the spec file (the modal pattern is dead) OR rewrite
  to assert the muted-span shape. Likely DELETE — the notifications modal
  scaffold is paused zone work.

### Cluster 3 — Discord/Slack pane Phase D restructure (6 fails) — REWRITE

- `settings_webhooks_spec.rb:30, 40, 75, 95, 105, 135` — assert old form shape
  (`have_field("everything", type: "checkbox")`). Phase D restructured into
  split URL form + per-toggle auto-save forms with `name="enabled"` +
  `data-leader-toggle="discord_every_notification"`. View specs
  (`_discord_pane_html_erb_spec.rb`, `_slack_pane_html_erb_spec.rb`) were
  already realigned in FA6 + FA11 — the SYSTEM specs were not.
- **Disposition:** rewrite assertions to target the new DOM (selectors like
  `[data-leader-toggle="slack_every_notification"]`). High value to keep —
  covers the end-to-end webhook save flow.

### Cluster 4 — /games revamp DOM drift (18 fails — biggest cluster) — REWRITE

- `games_index_spec.rb:25, 48, 202, 213, 223, 230, 237, 252, 269, 280` (10) —
  assert old nested-shelf headings (alphabetical
  `[Adventure, platformer, rpg]`) + old filter-row chip toggle behavior.
  /games went through Wave A/B/C/D revamps; system specs are stale.
- `games_platform_ownerships_spec.rb:30, 55, 89, 97, 105` (5) — assert OLD
  ownership editor link (`click_link "edit ownership"`) + chip lookup by old
  selector. Task #294 (BX) made ownership matrix inline-editable; the "edit
  ownership" link is gone.
- `games_steam_shelf_spec.rb:10` (1) — `have_content("no games yet.")` —
  empty-state copy was REMOVED per task #124.
- `igdb_add_game_spec.rb:42, 104` (2) — assert old IGDB modal copy
  ("add a game" — removed per task #338).
- `keyboard_grid_navigation_spec.rb:44` (1) — asserts `[data-keyboard-tile]`
  not present on /games. Tile keyboard nav got removed per /games revamp.
- **Disposition:** large rewrite job. Recommend deferring until the /games
  surface stops moving (post-/channels wave when polish slows).

### Cluster 5 — TOTP flow drift (1 fail) — REWRITE

- `password_reset_via_2fa_spec.rb:40` —
  `fill_in "code", with: ROTP::TOTP.new(seed).now`. Likely fails on the
  redirect/allowlist change from FA8 (auth_concern.rb) or an unrelated TOTP UI
  drift.
- **Disposition:** investigate; could be a small fix or a deeper flow drift.

### Cluster 6 — C-impl spec bugs (2 fails) — FIX

- `seeds_spec.rb:290` — "is idempotent" — my C-impl 3/4 conversion has a
  `Platform.unscoped.count == snapshot[:platforms]` assertion. The snapshot
  likely captures count BEFORE the seed runs and the second run adds more
  (Platform seed is NOT idempotent or the snapshot is wrong moment). Spec bug,
  not prod bug.
- `settings_spec.rb:603` — "flips the flag to running + stamps
  reindex_started_at before enqueueing" — my C-impl 4/4 `travel_to(freeze_time)`
  setup likely has a timing or queue-assertion shape issue. Spec bug.
- **Disposition:** small fixes to my own spec bodies; could be done quickly OR
  deferred with the rest.

## Why deferred

- 33 of 35 are SYSTEM specs (Capybara); fixing them requires extensive DOM
  walkthroughs + JS state setup, which is costly mid-flow.
- The /games revamp is largely complete; another iteration in the same area
  before /channels would compound the system-spec drift further.
- /channels phase will reactivate the navbar entries for channels and force a
  deliberate sweep across navbar + view assertion conventions; that's the
  natural time to bundle the system-spec consolidation.

## Re-engagement order (when /channels phase begins)

1. Cluster 1 (Collection refs) — pure delete, no rewrite. Trivial.
2. Cluster 6 (C-impl spec bugs) — 2 small fixes, untangle my own assertion
   bodies.
3. Cluster 2 (Notifications modal) — likely delete; if kept, rewrite to
   muted-span shape.
4. Cluster 5 (TOTP flow) — investigate single fail; might fold into the auth
   concern audit.
5. Cluster 3 (Discord/Slack panes) — rewrite to new DOM; ~30 min.
6. Cluster 4 (/games revamp drift, 18 fails) — biggest rewrite; do AFTER the
   /channels work to avoid re-drift.

## Cross-cutting note

`bin/test` (fast default) skips `type:system`. Add a periodic `bin/test all`
checkpoint (e.g., every N commits or before each phase close) to prevent
system-spec drift from accumulating silently. Currently CI runs the full suite
per `.github/workflows/ci.yml`, so the gate is there — but CI is on hiatus
until 2026-06-02 per `project_ci_hiatus_until_jun_2` memory, meaning local
`bin/test all` is the only gate right now.

## Iteration spec TODOs — accumulating during the consolidation pass

Code-only iteration changes that need spec coverage when the dedicated
consolidation phase runs. Each item lists the file(s) touched, what changed,
and the assertion shape the spec should cover.

### 2026-05-20 — TUI chip visual differentiation (Tui::ChipComponent)

- **File:** `app/assets/tailwind/application.css` (`.tui-chip` block).
- **Change:** added `cursor: default` to `.tui-chip` + variant-scoped
  `:hover` color locks so chips don't read as bracket-link affordances. Weight
  already 400 vs bracket-links at 600.
- **Spec shape:**
  - `spec/components/tui/chip_component_spec.rb` should assert the rendered
    chip carries no `cursor: pointer` style and that its computed style does
    not match the bracket-link hover shift. Component spec can't actually
    introspect CSS, so the practical assertion is structural — the chip is
    rendered as a plain `<span class="tui-chip tui-chip--<variant>">` with NO
    `<a>` ancestor wrapping inside the component. That contract pins the
    "informational, non-clickable" intent at the markup boundary; the CSS
    rules then enforce the visual layer.
  - A separate system spec (later) can hover the chip and confirm color does
    not change — but that's a Capybara concern that belongs in the system
    consolidation pass, not the unit pass.

### 2026-05-20 — TUI cursor focus indicator CSS

- **File:** `app/assets/tailwind/application.css` (new
  `[data-tui-cursor-focused="yes"]` rule near the `.pito-pane` block).
- **Change:** 2px solid `var(--section-accent)` outline with `-2px` offset
  overlays the focused pane's existing 1px section-border so the cursor
  position is visible as the user tabs / Ctrl+hjkl across panes.
- **Spec shape:**
  - `spec/system/tui_cursor_navigation_spec.rb` (new) — visit a workspace
    with multiple panes, press Tab, assert the FIRST `.pito-pane` element
    carries `data-tui-cursor-focused="yes"` and the others do not. Press Tab
    again, assert the attribute moved. The CSS layer is verified visually,
    not in spec — what the spec pins is the attribute placement contract
    that `tui_cursor_controller.js` ships.
  - Pair with a unit-level Stimulus controller spec under
    `spec/javascript/controllers/tui_cursor_controller_spec.js` (if the
    project's JS test infra supports it) — assert `applyFocus()` toggles the
    dataset attribute correctly.

### 2026-05-20 — Notes volume status alignment (settings stack pane)

- **File:** `app/controllers/settings_controller.rb`
  (`notes_volume_status_for_settings_pane` + new
  `notes_volume_path_for_settings_pane`).
- **Change:** the chip path now resolves to
  `ENV["PITO_NOTES_PATH"] || tmp/pito-notes` — the SAME root the breakdown
  table uses — so the two surfaces always agree. Previous bug: chip checked
  `docs/notes` (an unrelated design-doc directory) while the table read
  `tmp/pito-notes`.
- **Spec shape:** `spec/requests/settings_spec.rb` (existing) should pick up
  a regression test that stubs `ENV["PITO_NOTES_PATH"]` to a tmp dir, creates
  one file inside, and asserts the rendered HTML contains BOTH the
  `[writable]` chip label AND the matching `count`/`size` row for the
  `project` namespace — i.e., the chip and the breakdown reconcile. Without
  this regression test, the two-source drift can recur silently.
