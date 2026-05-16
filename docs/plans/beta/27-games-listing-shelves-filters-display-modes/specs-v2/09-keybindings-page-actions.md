# 09 — Keybindings: YAML-driven two-section reference (General + Page Actions)

> Phase 27 v2 spec. Re-architects the keybindings reference component
> around `config/keybindings.yml` as the SINGLE source of truth, feeding
> both the Rails web app and the future Rust TUI client. Introduces a
> two-section UI: a **General** block (navigation keys, available on
> every page) and a **Page actions** block (page-specific actions,
> omitted on pages that don't declare any). Drops the bulk-from-index
> actions (`- delete`, `r resync`) that no longer have a surface (per
> spec 05 dropping the list mode and bulk-select UI, and spec 08 making
> delete / resync per-game on the detail page).

---

## Goal

The keybindings reference becomes a living document driven by one YAML
file. Add a binding to `config/keybindings.yml` → both surfaces (Rails
web keybindings reference component, future Rust TUI keybindings
display) pick it up at next render. No second source of truth, no copy-
paste drift between the leader-menu popup, the help page, and the TUI.

The user sees two sections on every keybindings reference render:

1. **General** — navigation keys available everywhere (`g h home`, `g c
   calendar`, `g v videos`, etc.). Present on every page.
2. **Page actions** — actions specific to the current route (`/ search`,
   `s sync`, `- delete` on the game detail page). OMITTED on pages that
   declare no page actions (e.g. `/settings`).

---

## Scope in

### YAML — single source of truth

- `config/keybindings.yml` already exists in the project (created
  earlier for the unified leader-menu schema feeding both Rails web
  and Rust TUI). v2 EXTENDS the schema with two new top-level keys:
  - `general:` — list of `{key, label, action}` entries, available on
    every page. Preserves the current navigation map under
    `menus.root` / `menus.<resource>` (the leader-menu structure
    stays; the `general:` block is the FLAT view rendered on the
    keybindings reference, derived from the leader hierarchy or
    declared independently).
  - `page_actions:` — keyed by route pattern. Each route entry is a
    list of `{key, label, action, placeholder?, status?}` entries.
- `config/keybindings.yml` schema after this spec:

  ```yaml
  leader:
    key: " "
    display: "_"

  menus:
    # ... existing leader-menu hierarchy unchanged (root, calendar,
    # channels, videos, projects, games, bundles, notifications,
    # search, list_ops). The bulk-action rows REMOVED in this spec
    # are noted below.

  general:
    # Flat list of navigation keys available on EVERY page. Rendered
    # as the "General" section of the keybindings reference. Each
    # entry mirrors a leader-menu navigation row.
    items:
      - { key: "g h",  label: home,          action: { type: navigate, path: "/" } }
      - { key: "g c",  label: calendar,      action: { type: navigate, path: "/calendar/month" } }
      - { key: "g C",  label: channels,      action: { type: navigate, path: "/channels" } }
      - { key: "g V",  label: videos,        action: { type: navigate, path: "/videos" } }
      - { key: "g P",  label: projects,      action: { type: navigate, path: "/projects" } }
      - { key: "g G",  label: games,         action: { type: navigate, path: "/games" } }
      - { key: "g N",  label: notifications, action: { type: open, target: notifications_modal } }
      - { key: "g S",  label: settings,      action: { type: navigate, path: "/settings" } }
      - { key: q,      label: "quit + logout", action: { type: quit_and_logout } }

  page_actions:
    # Keyed by route pattern. Each entry is a list of page-specific
    # bindings rendered under "Page actions" when the current request
    # matches. Pages NOT keyed here render no page-actions section.
    "/games":
      - { key: "/", label: search, action: { type: page_search }, placeholder: true, status: tbd }
      - { key: "+", label: "add game", action: { type: open, target: igdb_search } }
    "/games/:id":
      - { key: "/", label: search, action: { type: page_search }, placeholder: true, status: tbd }
      - { key: s,   label: sync,   action: { type: page_sync } }
      - { key: "-", label: delete, action: { type: page_delete } }
    # /settings is INTENTIONALLY ABSENT — no page-actions section
    # renders on /settings (user explicitly said /settings is not a
    # daily-driven page; only general navigation matters there).
    # Calendar, channels, videos, projects, notifications: also
    # intentionally absent for now — page actions land when each
    # page reaches its own beta-3 revamp.
  ```

- Drop the following entries from `menus.*`:
  - `menus.games.items` — remove `{ key: "-", label: delete, action: {
    type: bulk_delete } }`.
  - `menus.games.items` — remove `{ key: r, label: resync, action: {
    type: bulk_resync } }`.
  - `menus.bundles.items` — remove `{ key: r, label: resync, action: {
    type: bulk_resync } }`.
  - `menus.bundles.items` — remove any `bulk_delete` row (audit
    + drop if present).

### Two-section UI

- Render the `general:` section on every page.
- Render the `page_actions:<route>` section ONLY when the current
  request's route key matches a `page_actions` entry. Route matching
  uses Rails' route name or path-pattern (see Behavior).
- `/settings` declares NO page-actions section → component renders
  ONLY the General section. The component MUST handle the empty-page-
  actions case cleanly (no empty heading, no stray separator).
- `/games` declares 2 page actions (`/`, `+`).
- `/games/:id` declares 3 page actions (`/`, `s`, `-`).
- All other pages: general only.

### `/` (search) placeholder modal

- The `/` key on `/games` and `/games/:id` opens a placeholder modal
  (`SearchPlaceholderModalComponent` or a shared inline render).
- Modal contents:
  - The `StatusTbdBadgeComponent` (defined in spec 08) rendering
    `[TBD]` in bright orange.
  - One-line muted copy: `"search revamp coming"`.
  - No input field. No `[search]` button. Just the badge + copy.
- Close on Esc OR click outside.
- Wired via the `page_search` action handler in
  `keyboard_controller.js`.

### Rails consumer

- `app/helpers/keybindings_helper.rb` (rework) — reads
  `config/keybindings.yml` and exposes:
  - `general_bindings -> Array<Hash>` — the `general:` block.
  - `page_action_bindings(route_key) -> Array<Hash> | nil` — the
    matching `page_actions[<route>]` block, or nil when the route
    has no entry.
  - `current_route_key(request) -> String` — translates a Rails
    request into the YAML route key. Default mapping:
    - `request.path == "/games"` → `"/games"`.
    - `request.path =~ /\A\/games\/[^\/]+\z/` → `"/games/:id"`.
    - else → nil (no page actions).
- `app/components/keybindings_reference_component.rb` (NEW or
  rewrite if existing)
  - Constructor: `initialize(current_route_key:)`.
  - Renders TWO `<section>` blocks: General + Page actions (the
    latter only when `page_action_bindings(current_route_key)`
    returns non-nil).
  - Each section: `<h3>` heading + a `<dl>` (or styled `<table>`)
    of `<key> · <label>` rows.
  - **Page actions render BEFORE General is a project convention
    candidate; v2 lands page actions BELOW general** for now
    (open question — confirm during review).
  - Loaded YAML at boot (Rails initializer caches the parsed
    Hash). In `Rails.env.development`, the helper re-reads the
    YAML per request for fast iteration; in test / production,
    the cached parse is used.

### Future TUI parity contract

- The Rust TUI client (`pito` binary, `extras/cli/`) reads the SAME
  YAML at boot and renders its own keybindings overlay from the
  same `general:` + `page_actions:` structure. v2 ships only the
  Rails web half; the TUI side lands in a later CLI lane.
- The schema is designed to be surface-agnostic: `action.type`
  values are abstract resolvers (`page_search`, `page_sync`,
  `page_delete`, `navigate`, `open`, `quit_and_logout`). Each
  surface (web vs TUI) wires its own resolver to map type →
  concrete behavior.
- Optional `surfaces:` key on a single entry restricts that entry
  to one surface (e.g. `surfaces: [tui]` for `q quit` which only
  makes sense in the TUI). Both surfaces filter the parsed YAML
  by surface at render time.

### Cross-cutting: every page renders the reference

- The keybindings reference component renders on every page (likely
  via a layout-level partial or a help-overlay triggered by `?` key).
- The implementation agent MUST verify all pages still render
  correctly after the edit — not just `/games`. Particular attention
  to:
  - `/settings` — no page-actions section. Component must render
    cleanly without an empty heading or trailing separator.
  - `/calendar/month`, `/channels`, `/videos`, `/projects` — also
    no page-actions section currently. Same rendering check.
  - `/games` — 2 page actions.
  - `/games/:id` — 3 page actions.
  - Any auth gate page (`/login`, `/settings/security/totp/new` —
    the mandatory-2FA gate) — confirm the keybindings reference is
    NOT rendered on auth-only screens (or renders only General if
    it is rendered).

## Scope out

- Other resource keybindings (channels, videos, projects, calendar,
  notifications) — page-action entries land when each page reaches
  its own beta-3 revamp. v2 only adds entries for `/games` and
  `/games/:id`.
- The leader-menu rendering itself (Stimulus controller + CSS) —
  unchanged.
- The CLI / Ratatui implementation of the new sections — schema is
  shared, but rendering is a separate CLI lane.
- The TUI's per-pane action plumbing.
- An auth-page audit beyond confirming the keybindings component
  does not crash on login / TOTP-enrollment pages.

---

## Files to change

### Schema

- `config/keybindings.yml`
  - In `menus.games.items`:
    - Remove the row `{ key: "-", label: delete, action: { type:
      bulk_delete } }`.
    - Remove the row `{ key: r, label: resync, action: { type:
      bulk_resync } }`.
  - In `menus.bundles.items`:
    - Remove the row `{ key: r, label: resync, action: { type:
      bulk_resync } }`.
    - Audit + remove any `bulk_delete` row (if present).
  - ADD a new top-level `general:` key (see schema above).
  - ADD a new top-level `page_actions:` key (see schema above).
  - Update the file's docstring (top comment block) to document
    the two new sections and their relationship to the existing
    `menus.*` hierarchy.

### Stimulus controller

- `app/javascript/controllers/keyboard_controller.js`
  - Wire the three new action types:
    - `page_search` → finds the `data-page-search-modal-id`
      attribute (or fallback `searchPlaceholderModal`) and opens
      the matching `<dialog>` via showModal(). Reads the YAML
      entry's `placeholder: true` and renders the TBD badge body.
      When the attribute is absent → no-op.
    - `page_sync` → finds the `data-page-sync-url` attribute on
      `<body>` (or a designated wrapper) and POSTs to it via a
      Stimulus action / fetch. The detail page's wrapper emits
      `data-page-sync-url="/games/:id/resync"`. When the attribute
      is absent → no-op.
    - `page_delete` → finds the `data-page-delete-modal-id`
      attribute and dispatches a click on the corresponding
      hidden `<button>` that triggers the confirm modal open.
      When the attribute is absent → no-op.
- `app/javascript/controllers/leader_menu_controller.js`
  - When rendering the leader popup, do NOT show `page_actions`
    as a sub-menu under `G` (page actions are a separate keybindings
    concept, not a leader-menu drilldown). The keybindings
    reference page surfaces them as a documentation section.

### View

- `app/views/games/show.html.erb` (rewritten in spec 08 — coordinate)
  - Add `data-page-sync-url="<%= resync_game_path(@game) %>"` and
    `data-page-delete-modal-id="game_delete_modal_<%= @game.id %>"`
    to the page wrapper (the topmost `<div>` inside the
    Rails-rendered body fragment).
  - Add `data-page-search-modal-id="search_placeholder_modal"` so
    the `/` key opens the search placeholder modal.
- `app/views/games/index.html.erb`
  - Add `data-page-search-modal-id="search_placeholder_modal"` so
    the `/` key on `/games` opens the search placeholder modal
    (NOT the IGDB add-game modal; `+` is the dedicated key for
    that).
- `app/views/shared/_search_placeholder_modal.html.erb` (NEW)
  - Renders a single `<dialog>` with id `search_placeholder_modal`.
  - Body: `StatusTbdBadgeComponent` + muted `"search revamp coming"`.
  - Wire `Esc` close via the existing modal pattern.
  - Rendered in the application layout so every page can target it.

### Components

- `app/components/keybindings_reference_component.rb` (NEW or
  rewrite if existing)
  - Two `<section>` blocks (General + Page actions, the latter
    omitted when nil).
  - Reads via `keybindings_helper`.
- `SearchPlaceholderModalComponent` — optional; the partial
  approach above suffices unless the project favors components for
  every modal. Pick at implementation.

### Keybindings reference page / surface

- Locate the existing keybindings reference page (likely under a
  Settings page or a `/keybindings` route — audit during
  implementation). If it does not exist as a dedicated page,
  surface as an open question — the YAML is the source of truth,
  and the reference component is the user-facing surface.
- Render `general` + `page_actions[current_route_key]` per the
  two-section structure.

### Spec / fixture cleanup

- `spec/helpers/keybindings_helper_spec.rb` — extend to assert:
  - `menus.games.items` no longer contains `bulk_delete` or
    `bulk_resync` rows.
  - `menus.bundles.items` no longer contains `bulk_resync`.
  - `general.items` contains the navigation bindings (size +
    composition).
  - `page_actions["/games"]` contains 2 items (`/`, `+`).
  - `page_actions["/games/:id"]` contains 3 items (`/`, `s`, `-`).
  - `page_actions["/settings"]` is NIL (not present).
- `spec/system/leader_menu_spec.rb` — drop assertions that the `G`
  submenu shows `- delete` or `r resync`. Add assertion that the
  `G` submenu now shows only `l list` + `+ new` + `B bundles`.
- `spec/components/keybindings_reference_component_spec.rb` (NEW
  or extend):
  - With `current_route_key: "/games"`: renders General +
    2-item Page actions.
  - With `current_route_key: "/games/:id"`: renders General +
    3-item Page actions.
  - With `current_route_key: "/settings"`: renders ONLY General,
    NO page-actions section, NO empty heading.
  - With `current_route_key: nil` (page with no mapping):
    renders ONLY General.

---

## Behavior contracts

### YAML schema (post-spec)

```yaml
leader:
  key: " "
  display: "_"

menus:
  root: { ... unchanged ... }
  calendar: { ... unchanged ... }
  channels: { ... unchanged ... }
  videos: { ... unchanged ... }
  projects: { ... unchanged ... }
  games:
    items:
      - { key: l, label: list, action: { type: navigate, path: "/games" } }
      - { key: "+", label: new, action: { type: open, target: igdb_search } }
      - { key: B, label: bundles, submenu: bundles }
  bundles:
    items:
      - { key: l, label: list, action: { type: navigate, path: "/bundles" } }
      - { key: "+", label: new, action: { type: open, target: new_bundle } }
  notifications: { ... unchanged ... }
  search: { ... unchanged ... }
  list_ops: { ... unchanged ... }

general:
  items:
    - { key: "g h",  label: home,          action: { type: navigate, path: "/" } }
    - { key: "g c",  label: calendar,      action: { type: navigate, path: "/calendar/month" } }
    - { key: "g C",  label: channels,      action: { type: navigate, path: "/channels" } }
    - { key: "g V",  label: videos,        action: { type: navigate, path: "/videos" } }
    - { key: "g P",  label: projects,      action: { type: navigate, path: "/projects" } }
    - { key: "g G",  label: games,         action: { type: navigate, path: "/games" } }
    - { key: "g N",  label: notifications, action: { type: open, target: notifications_modal } }
    - { key: "g S",  label: settings,      action: { type: navigate, path: "/settings" } }
    - { key: q,      label: "quit + logout", action: { type: quit_and_logout } }

page_actions:
  "/games":
    - { key: "/", label: search, action: { type: page_search }, placeholder: true, status: tbd }
    - { key: "+", label: "add game", action: { type: open, target: igdb_search } }
  "/games/:id":
    - { key: "/", label: search, action: { type: page_search }, placeholder: true, status: tbd }
    - { key: s,   label: sync,   action: { type: page_sync } }
    - { key: "-", label: delete, action: { type: page_delete } }
```

### Per-page contracts (post-spec)

| Route          | General | Page actions                                  |
| -------------- | ------- | --------------------------------------------- |
| `/`            | yes     | none                                          |
| `/settings`    | yes     | **NONE** (explicit, not daily-driven)         |
| `/calendar/*`  | yes     | none (until calendar revamp)                  |
| `/channels`    | yes     | none (until channels revamp)                  |
| `/channels/*`  | yes     | none                                          |
| `/videos`      | yes     | none (until videos revamp)                    |
| `/videos/*`    | yes     | none                                          |
| `/projects`    | yes     | none (until projects revamp)                  |
| `/projects/*`  | yes     | none                                          |
| `/games`       | yes     | `/ search (placeholder)`, `+ add game`        |
| `/games/:id`   | yes     | `/ search (placeholder)`, `s sync`, `- delete` |
| `/notifications*` | yes  | none (until notifications revamp)             |

### `/games` page actions

- `/` (search) — opens `SearchPlaceholderModalComponent` (or the
  shared partial). The modal shows `[TBD]` badge + "search revamp
  coming" copy. Esc closes.
- `+` (add game) — opens the IGDB add-game modal (per spec 04).
  This is the SOLE entry to creating a game (spec 04's locked
  contract).

### `/games/:id` page actions

- `/` (search) — opens the same placeholder modal as `/games`.
- `s` (sync) — POSTs to `/games/:id/resync` (per spec 03). The
  sync banner flips to `=---` while in flight (muted styling on
  the breadcrumb `[resync]`). Re-pressing `s` while in flight is
  a no-op (the controller's existing `resyncing?` guard short-
  circuits).
- `-` (delete) — opens the per-page delete confirm modal (per
  spec 08).

### `/settings` — no page actions section

- The keybindings reference component renders ONLY the General
  section on `/settings`. No `<h3>Page actions</h3>` heading, no
  empty `<dl>`, no trailing separator. Confirm via system spec.

### Discoverability

- The leader menu popup does NOT drill into `page_actions` from `G`.
- The keybindings reference page (wherever it lives) renders
  Page actions and General as two sibling sections so a user
  looking up "what does `s` do" finds it immediately.

### No JS confirm / no inline destructive

- The `s` and `-` page actions ROUTE TO existing destructive
  surfaces (the resync POST and the confirm modal). No new
  confirm dialogs are created here.

### Component empty-case handling (LOCKED)

- `KeybindingsReferenceComponent`, when
  `page_action_bindings(current_route_key)` returns nil:
  - Does NOT render a `<section>` for Page actions.
  - Does NOT render an `<h3>` heading.
  - Does NOT render any separator between General and the
    absent Page actions block.
  - Renders ONLY the General section, cleanly.
- This behavior is asserted in the component spec.

---

## Migrations

None.

---

## ViewComponents

- `KeybindingsReferenceComponent` (NEW or rewrite).
- `SearchPlaceholderModalComponent` (NEW or partial). Renders
  `StatusTbdBadgeComponent` (defined in spec 08) + muted copy.
- `StatusTbdBadgeComponent` — REUSED (defined in spec 08; not
  introduced here).

---

## Stimulus controllers

- `keyboard_controller.js` extended (3 new action handlers:
  `page_search`, `page_sync`, `page_delete`).
- `leader_menu_controller.js` audit — confirm it skips
  `page_actions` for popup rendering.

---

## Spec coverage required

### Schema spec (`spec/helpers/keybindings_helper_spec.rb`)

- `menus.games.items` size + composition (3 items: l, +, B).
- `menus.bundles.items` size + composition (2 items: l, +).
- `general.items` size + composition (matches the navigation map).
- `page_actions["/games"]` size = 2; keys `["/" "+"]`.
- `page_actions["/games/:id"]` size = 3; keys `["/" "s" "-"]`.
- `page_actions["/settings"]` is nil.
- `surfaces:` filtering still works — passing `:web` returns the
  same shape; passing `:tui` returns the same shape (no
  `surfaces:` keys on the new items means both surfaces see
  them).

### Component spec (`spec/components/keybindings_reference_component_spec.rb`)

- With `current_route_key: "/games"`: renders General section +
  Page actions section with 2 rows.
- With `current_route_key: "/games/:id"`: renders General +
  3-row Page actions.
- With `current_route_key: "/settings"`: renders ONLY General.
  No `<h3>Page actions</h3>`. No empty `<dl>`. No trailing
  hairline.
- With `current_route_key: nil`: same as `/settings`.
- The `placeholder: true` + `status: tbd` flags on a page-action
  entry render an inline `[TBD]` badge next to the key/label.

### Stimulus / system spec (`spec/system/games_page_actions_spec.rb`,
NEW)

- ONE scenario per per-page binding:
  - On `/games/:id`, pressing `s` → POSTs resync → flash visible.
  - On `/games/:id`, pressing `-` → confirm modal opens.
  - On `/games/:id`, pressing `/` → search placeholder modal
    opens; shows `[TBD]` + "search revamp coming"; Esc closes.
  - On `/games`, pressing `/` → search placeholder modal opens.
  - On `/games`, pressing `+` → IGDB add-game modal opens.
  - On `/games`, pressing `s` → nothing happens (no error, no
    flash, no navigation).
  - On `/games`, pressing `-` → nothing happens.

### Settings empty-page-actions spec (`spec/system/settings_keybindings_spec.rb`,
NEW)

- Visit `/settings`. The keybindings reference component renders
  ONLY the General section. No `<h3>Page actions</h3>` heading
  appears. The page does not error.
- Visit `/calendar/month`, `/channels`, `/videos`, `/projects`
  → same assertion (general only). One round-trip per route.

### Leader-menu spec (`spec/system/leader_menu_spec.rb`)

- Pressing leader → `G` opens a 3-item popup (`l`, `+`, `B`).
  No `-` row, no `r` row.
- Pressing leader → `G` → `B` opens a 2-item popup (`l`, `+`).
- Pressing leader does NOT show `page_actions` as a submenu.

### Keybindings reference page spec

- If the page exists, assert the two sections render in
  declared order (General + Page actions; or vice versa per
  the locked decision below).
- If the page does NOT exist (audit shows no
  `/settings/keybindings` or equivalent), surface as an open
  question — the schema is the source of truth and the
  component is the canonical user-facing surface.

---

## Manual test recipe

1. `bin/dev` → open the leader menu (space) → press `G`. The
   popup shows `l list`, `+ new`, `B bundles`. No `-` row, no
   `r` row.
2. Press `B` → popup shows `l list`, `+ new`. No `r` row.
3. Press Esc.
4. Open `/games/:id` (any game). Press `s` (no leader). The
   sync banner flips to the `=---` indicator (per spec 03).
5. On `/games/:id`, press `-`. The delete confirm modal opens
   (per spec 08). Press Esc to close.
6. On `/games/:id`, press `/`. The search placeholder modal
   opens; body shows orange `[TBD]` badge and "search revamp
   coming". Press Esc to close.
7. Open `/games`. Press `s`. Nothing happens (no flash, no
   navigation, no console error).
8. On `/games`, press `-`. Nothing happens.
9. On `/games`, press `/`. Search placeholder modal opens.
10. On `/games`, press `+`. IGDB add-game modal opens.
11. Visit `/settings`. The keybindings reference shows ONLY the
    General section. No `Page actions` heading appears.
12. Visit `/calendar/month` → same (General only). Repeat for
    `/channels`, `/videos`, `/projects` to confirm the empty-
    page-actions case renders cleanly everywhere.
13. Visit the keybindings reference page (audit during
    implementation). General section lists `g h home`, `g c
    calendar`, etc.; Page actions section (only on supported
    routes) lists the per-page entries.

---

## Open questions

1. **Section render order — General first or Page actions first?**
   User said "page actions BEFORE navigation" in the original 09
   draft; revisit. Architect lean: Page actions FIRST (since
   they're the immediate, context-specific affordances and
   General is the always-true navigation map). Confirm during
   review.
2. **Does a dedicated keybindings reference page exist (e.g.
   `/settings/keybindings` or `/help/keys`)?** Audit during
   implementation. If not, the component renders inline (e.g.
   via `?` keypress overlay or a settings section). Surface as
   architect follow-up if no surface exists.
3. **YAML reload cadence — boot-only cache vs per-request reload
   in development.** Architect lean: per-request reload in dev,
   boot-cache in test/prod for performance.
4. **Cross-stack — Rust CLI surface parity.** Architect lean:
   defer. The CLI parses the same YAML; the new entries become
   visible in the CLI's keybindings overlay automatically. CLI-
   side wiring of `page_sync` / `page_delete` action handlers is
   a separate CLI lane.
5. **Bundles bulk-delete row** — confirm whether it exists in
   the current schema (audit `config/keybindings.yml`'s
   `menus.bundles.items` body). If yes, drop it for the same
   reason `r resync` drops; if no, no-op.
6. **`general:` block — derived from `menus.*` automatically OR
   declared independently?** v2 declares it independently (above)
   for clarity. Alternative: a small helper walks the leader
   hierarchy to derive the flat list. Pick at implementation;
   declared-independently is the safer default (avoids surprise
   when the leader hierarchy reshapes).
