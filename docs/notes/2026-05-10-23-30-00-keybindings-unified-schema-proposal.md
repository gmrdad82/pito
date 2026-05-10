# Keybindings — unified schema proposal (2026-05-10)

## Goal

Both the Rails web app and the Rust TUI share a single source of truth for
keybindings + leader-menu structure. Edit one file, both stacks pick it up.

## Source of truth

`config/keybindings.yml` at the repo root. Format chosen because:

- Rails reads natively via `Rails.application.config_for(:keybindings)`
- Rust reads natively via `serde_yaml` (already in the dep graph posture)
- Human-readable for review

If YAML doesn't fit later, fallback is a single tracked `docs/keybindings.md`
that both stacks parse lightly. YAML is the better starting point.

## Visual posture

- Replace `[?]` in the navbar with `[_]` — `_` represents the SPACE leader.
- Press SPACE (or click `[_]`) → small popup anchored bottom-right (NOT
  centered). Lists current-menu items as `[key] label` rows.
- Submenu opens by replacing popup contents (no nested popups).
- `Esc` closes the popup entirely.
- `Backspace` goes up one level. Pressing leader from inside a submenu also
  closes (LazyVim behavior).
- TUI mirrors this: `[_]` indicator in the status bar; SPACE opens a Ratatui
  overlay at bottom-right; same navigation rules.
- Remove the trailing `·` separator before `[settings]` in the navbar.

## Root menu (level 0)

```
h home
c calendar       -> calendar submenu
C channels       -> channels submenu
V videos         -> videos submenu
P projects       -> projects submenu
G games          -> games submenu
N notifications  -> notifications submenu
S settings       -> direct nav
/ search         -> search submenu
q quit (TUI only)
Q quit + logout
```

Capital letters = global resource pages. Lowercase letters = qualifiers /
actions.

## Per-surface submenus

### Calendar

Calendar has no separate list — schedule IS the list. So `l` is omitted; `s` is
schedule (the list-like view) and `m` is month.

```
s schedule (acts as list)
m month
t today (jump to today on current view)
+ new entry (POST -> "Untitled event", redirect to /edit)
```

### Channels

```
l list
+ add
b bulk-mode toggle
- bulk delete
s bulk sync
```

Dropped: `*` bulk star toggle (star is per-row, not useful in bulk).

### Videos

No `+` — videos come from channel sync, not direct add.

```
l list
b bulk-mode toggle
- bulk delete
```

### Projects

```
l list
+ new
b bulk-mode toggle
- bulk delete
```

Dropped: `p` pin/unpin (pin is per-row).

### Games

```
l list (Steam shelf)
+ new (opens IGDB modal — same as global hotkey i)
b bulk-mode toggle
- bulk delete
r bulk resync
B bundles -> bundle submenu
```

Bundle submenu (`G B`):

```
l list
+ new
r bulk resync
```

### Notifications

```
l list
u filter unread
m mark all as read
```

### Settings

Direct navigate to `/settings`. No submenu.

### Search

```
/ global pito search (modal)
C channels search
V videos search
P projects search
G games search
g igdb search (same as global hotkey i)
```

## Conventions baked in

- `l` = list (always means navigate to /<resource>)
- `+` = new (always opens add/new flow)
- `b` = bulk-mode toggle
- `-` = bulk delete
- `s` / `r` = sync / resync
- `t` = today (calendar-only)
- `Esc` = cancel / close popup
- `Backspace` = up one level

Same letter means the same kind of action across surfaces. Reduces cognitive
load.

## What I considered but left out

- **Footage.** CLI-only today (`pito footage`). Schema supports per-surface
  visibility via `surfaces: [tui]` filter. Web entry can land later if a web
  surface ships.
- **Saved views.** Today each surface has its own. A global `v` submenu was
  considered but adds friction; keep per-surface for now.
- **Notes.** Scoped to projects; no top-level index worth a leader binding.
- **Timelines.** Retired from project show; not in menu.
- **Analytics.** Per-context (channel/video). No top-level menu — accessed via
  the channel/video show pages.
- **Theme.** Page-level shortcut (`n -> t`) already exists. Not under leader.
- **MCP / Sidekiq / admin.** Skipped.

## Implementation plan

1. **Schema lock.** Write `config/keybindings.yml` matching the structure above.
2. **Rails web.**
   - Loader at boot: render schema-as-JSON into the layout, available to
     Stimulus.
   - `leader_menu_controller.js` reads it, handles SPACE / Esc / Backspace / key
     presses.
   - `[?]` -> `[_]` in navbar.
   - Drop the trailing `·` before `[settings]`.
   - Old `keyboard_shortcuts_modal_component` repurposed or retired (the leader
     menu IS the help surface — items are always visible).
3. **Rust TUI.**
   - `serde_yaml::from_str` loader at `extras/cli/src/keybindings.rs`.
   - Ratatui overlay widget at bottom-right.
   - `[_]` indicator added to the status bar.
4. **Companion doc.** Optional: a `docs/keybindings.md` that lists every binding
   (auto-rendered from YAML, or hand-kept in sync). Useful for PR review.
5. **TUI keymap migration.** Existing CLI keymap (j/k navigation, etc.) stays
   page-level; only the leader-menu is moved to the unified schema.
6. **Web in-row hotkeys.** Existing in-row shortcuts (j/k navigation, /, i,
   etc.) stay page-level; only the leader-menu is unified.

## Open items waiting on user

None blocking. Three minor defaults I picked autonomously:

- `*` bulk star (channels) — DROPPED. Per-row only.
- `p` pin (projects) — DROPPED. Per-row only.
- Theme toggle — STAYS page-level. Not under leader.

User can flip any of these on review.

## What's missing

- The dispatch order for sub-spec 11i (channel-diff cron) might want to reserve
  a per-channel diff-banner keybind (e.g. `d` on channel show page), but that is
  page-level, not leader. Captured for the Step 11 ship.
- TUI vs web symmetry on `q` — web treats `q` as Esc alias; TUI exits process.
  Documented in the schema via a `surfaces` filter.
- Bulk-mode interactions: when bulk mode is on, do menu items change? Today's
  posture says no — items always show; if no rows selected, the action no-ops or
  surfaces a flash.

## Mobile next step

After validation, dispatch:

- Schema + Rails wiring (docs-keeper writes the YAML, rails agent does the
  Stimulus refactor).
- TUI Ratatui overlay (rust agent).
- Both can land in parallel; the schema is the contract.
