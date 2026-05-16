# 09 — Keybindings: drop bulk delete/resync, add page-actions section

> Phase 27 v2 spec. Cleans up the unified leader-menu schema in
> `config/keybindings.yml` to drop the bulk-from-index actions
> (`- delete`, `r resync`) that no longer have a surface (per spec 05
> dropping the list mode and bulk-select UI, and spec 08 making delete /
> resync per-game on the detail page). Adds a new "page actions"
> section to the keybindings reference, placed BEFORE the navigation
> section (per the user's stated preference). Documents per-page
> behavior for `/`, `s`, and `-` on the games index and game detail
> page.

---

## Goal

The leader menu under `G` (games) and `G → B` (bundles) advertises only
the actions that exist. Bulk delete and bulk resync are gone (their UI
surfaces died with spec 05's grid/list modes and spec 08's per-game
delete modal). In their place, the keybindings reference grows a new
"page actions" section listing per-page keybindings — the keys that act
on whatever the user is currently looking at, not on a navigation
target.

---

## Scope in

- Edit `config/keybindings.yml`:
  - REMOVE `- delete` from `menus.games.items`.
  - REMOVE `r resync` from `menus.games.items`.
  - REMOVE `r resync` from `menus.bundles.items`.
  - Optionally REMOVE `- delete` from `menus.bundles.items` if it
    exists (audit and decide — bundles also lost their bulk surface).
- Add a NEW menu key `page_actions` to the schema with the per-page
  bindings.
- Reorder the keybindings reference page so the new `page_actions`
  section renders BEFORE the navigation section (per user
  preference).
- Per-page binding table:

  | Key | Page                | Behavior                                       |
  | --- | ------------------- | ---------------------------------------------- |
  | `/` | `/games`            | Open the existing search modal (`yt:games`).   |
  | `/` | `/games/:id`        | Open the existing search modal (`yt:games`).   |
  | `s` | `/games/:id`        | Trigger resync (per spec 03's job + lock).     |
  | `s` | `/games` (no row focus) | No-op (or open IGDB search — pick; arch lean: no-op). |
  | `-` | `/games/:id`        | Open the per-page delete confirm modal (per spec 08). |
  | `-` | `/games`            | No-op (no bulk-select surface).                |

  Plus the same for bundles (when applicable): `s` triggers per-bundle
  resync on `/bundles/:id`, `-` opens per-bundle delete modal.

## Scope out

- Other resource keybindings (channels, videos, projects) — untouched.
- The leader-menu rendering itself (Stimulus controller + CSS).
- The CLI / Ratatui implementation of the new `page_actions` section
  (the schema flag `surfaces: [web, tui]` covers both, but the CLI's
  ratatui rendering of page-action helpers is a separate CLI lane).
  Document but defer.
- The TUI's per-pane action plumbing.

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
  - Add a new top-level `menus.page_actions` key:
    ```yaml
    page_actions:
      items:
        - { key: "/", label: search,    action: { type: page_search } }
        - { key: s,   label: sync,      action: { type: page_sync } }
        - { key: "-", label: delete,    action: { type: page_delete } }
    ```
  - The `action.type` values are new — document in the schema
    docstring at the top of the file. The leader-menu controller maps
    them to per-page resolvers.

### Stimulus controller

- `app/javascript/controllers/keyboard_controller.js`
  - Wire the three new action types:
    - `page_search` → opens the existing search modal (already
      bound to `/` outside the leader menu; the new action just
      makes it discoverable in the keybindings reference).
    - `page_sync` → finds the `data-page-sync-url` attribute on
      `<body>` (or a designated wrapper) and POSTs to it via a
      Stimulus action / fetch. The detail page's body
      (or wrapping div) emits `data-page-sync-url="/games/:id/resync"`.
      When the attribute is absent → no-op.
    - `page_delete` → finds the `data-page-delete-modal-id`
      attribute and dispatches a click on the corresponding
      hidden `<button>` that triggers the confirm modal open.
      When the attribute is absent → no-op.
- `app/javascript/controllers/leader_menu_controller.js`
  - When rendering the leader popup, do NOT show `page_actions`
    as a sub-menu under `G` (it is a global concept; the popup
    doesn't drill into it). The keybindings reference page
    surfaces it as a documentation section.

### View

- `app/views/games/show.html.erb` (rewritten in spec 08 — coordinate)
  - Add `data-page-sync-url="<%= resync_game_path(@game) %>"` and
    `data-page-delete-modal-id="game_delete_modal_<%= @game.id %>"`
    to the page wrapper (the topmost `<div>` inside the
    Rails-rendered body fragment).
- `app/views/games/index.html.erb`
  - Add `data-page-search-modal-id="igdb-search-modal"` so the `/`
    key on `/games` opens the existing IGDB search modal. This
    matches the existing behavior (the search modal already opens
    on `/` via a separate keyboard handler) — wire through the
    schema so it shows up in the reference.
- Bundles equivalents: same wrapper attributes on
  `app/views/bundles/show.html.erb`.

### Keybindings reference page

- Locate the existing keybindings reference (likely under a
  Settings page or a `/keybindings` route — audit during
  implementation). If it does not exist as a dedicated page,
  surface as an open question.
- Render `page_actions` as a section BEFORE the navigation section.
- For each item, document the per-page behavior in a small table
  so the user can see what `s` does on `/games/:id` vs `/games`.

### Spec / fixture cleanup

- `spec/helpers/keybindings_helper_spec.rb` — extend to assert:
  - `menus.games.items` no longer contains `bulk_delete` or
    `bulk_resync` rows.
  - `menus.bundles.items` no longer contains `bulk_resync`.
  - `menus.page_actions.items` contains exactly three entries:
    `["/" search, s sync, - delete]`.
- `spec/system/leader_menu_spec.rb` — drop assertions that the `G`
  submenu shows `- delete` or `r resync`. Add assertion that the
  `G` submenu now shows only `l list` + `+ new` + `B bundles`.

---

## Behavior contracts

### `G` submenu (post-spec)

```yaml
games:
  items:
    - { key: l, label: list, action: { type: navigate, path: "/games" } }
    - { key: "+", label: new, action: { type: open, target: igdb_search } }
    - { key: B, label: bundles, submenu: bundles }
```

### `G → B` submenu (post-spec)

```yaml
bundles:
  items:
    - { key: l, label: list, action: { type: navigate, path: "/bundles" } }
    - { key: "+", label: new, action: { type: open, target: new_bundle } }
```

### `page_actions` schema entry

```yaml
page_actions:
  items:
    - { key: "/", label: search,    action: { type: page_search } }
    - { key: s,   label: sync,      action: { type: page_sync } }
    - { key: "-", label: delete,    action: { type: page_delete } }
```

### Per-page binding behavior

- `/` (search):
  - `/games` → opens IGDB add-game modal (or the global search
    modal if one is wired separately — pin behavior at
    implementation; architect lean: IGDB add-game modal, since
    `/games` doesn't have a separate "filter by name" surface yet).
  - `/games/:id` → opens the same global search modal.
- `s` (sync):
  - `/games/:id` → POSTs to `/games/:id/resync`. Equivalent to
    clicking the breadcrumb `[resync]` link.
  - `/games` → no-op (no row focus means no game to sync).
- `-` (delete):
  - `/games/:id` → opens the per-page delete confirm modal (per
    spec 08).
  - `/games` → no-op.

### Discoverability

- The leader menu popup does NOT drill into `page_actions` from `G`.
- The keybindings reference page renders `page_actions` as its
  first section (before "navigation") so a user looking up "what
  does `s` do" finds it immediately.

### No JS confirm / no inline destructive

- The `s` and `-` page actions ROUTE TO existing destructive
  surfaces (the resync POST and the confirm modal). No new
  confirm dialogs are created here.

---

## Migrations

None.

---

## ViewComponents

None new.

---

## Stimulus controllers

- `keyboard_controller.js` extended (3 new action handlers).
- `leader_menu_controller.js` audit — confirm it skips
  `page_actions` for popup rendering.

---

## Spec coverage required

### Schema spec (`spec/helpers/keybindings_helper_spec.rb`)

- `menus.games.items` size + composition.
- `menus.bundles.items` size + composition.
- `menus.page_actions.items` exists with exactly 3 items in the
  declared order.
- `surfaces:` filtering still works — passing `:web` returns the
  same shape; passing `:tui` returns the same shape (no
  `surfaces:` keys on the new items means both surfaces see
  them).

### Stimulus / system spec (`spec/system/games_page_actions_spec.rb`,
NEW)

- ONE scenario per per-page binding:
  - On `/games/:id`, pressing `s` → POSTs resync → flash visible.
  - On `/games/:id`, pressing `-` → confirm modal opens.
  - On `/games`, pressing `/` → IGDB add-game modal opens.
  - On `/games`, pressing `s` → nothing happens (no error, no
    flash, no navigation).
  - On `/games`, pressing `-` → nothing happens.

### Leader-menu spec (`spec/system/leader_menu_spec.rb`)

- Pressing leader → `G` opens a 3-item popup (`l`, `+`, `B`).
  No `-` row, no `r` row.
- Pressing leader → `G` → `B` opens a 2-item popup (`l`, `+`).
- Pressing leader does NOT show `page_actions` as a submenu.

### Keybindings reference page spec

- If the page exists, assert `page_actions` section renders
  before `navigation`.
- If the page does NOT exist (audit shows no
  `/settings/keybindings` or equivalent), surface as an open
  question — the schema is the source of truth and the
  reference page is a docs concern.

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
6. On `/games/:id`, press `/`. The global search modal (IGDB
   add-game) opens. Press Esc to close.
7. Open `/games`. Press `s`. Nothing happens (no flash, no
   navigation, no console error).
8. On `/games`, press `-`. Nothing happens.
9. On `/games`, press `/`. IGDB add-game modal opens.
10. Visit the keybindings reference page. The first section is
    `page actions`, listing `/ search`, `s sync`, `- delete`
    with per-page behavior columns.

---

## Open questions

1. **Does a dedicated keybindings reference page exist?** Audit
   during implementation. If not, the schema is the source of
   truth and the user's view of the bindings is the leader menu
   popup itself. Surface as architect follow-up.
2. **On `/games`, what does `/` do — open the global search
   modal OR the IGDB add-game modal?** Architect lean: the
   IGDB add-game modal (the existing `i` keypress also opens
   it, and `/` is a natural alias on a page that doesn't have
   a filter-by-name search). Confirm.
3. **`s` on `/games` (no row focus) — true no-op, OR
   bulk-resync the currently-filtered set?** Architect lean:
   true no-op; bulk-resync is the surface we just dropped from
   the leader menu and should not return through a back door.
4. **Cross-stack — does the Rust CLI surface respect the new
   `page_actions` schema entry?** Architect lean: defer.
   The CLI parses the same YAML; the new entries become
   visible in the CLI's leader overlay automatically. CLI-side
   wiring of `page_sync` / `page_delete` action handlers is a
   separate CLI lane.
5. **Bundles bulk-delete row** — confirm whether it exists in
   the current schema (audit `config/keybindings.yml`'s
   `menus.bundles.items` body). If yes, drop it for the same
   reason `r resync` drops; if no, no-op.
