# Phase 7.5 — Step 04 — Rails Keyboard Shortcuts (mirroring the `pito` CLI)

> Implementation-ready spec. Adds a keyboard-shortcut layer to the Rails web app
> that mirrors the `pito` CLI's keymap. Depends on the CLI hygiene sweep landing
> first (`02-cli-hygiene-sweep.md`) so the CLI's keymap is at parity-baseline
> before Rails copies it.

---

## Goal

Surface a complete keyboard-shortcut layer in the Rails web app whose schema
mirrors the `pito` CLI's keymap exactly (Q6 default = strict mirror). The schema
lets the user navigate, filter, bulk-select, star, sync, and confirm without
leaving the keyboard, and surfaces a `?` help modal listing every binding.

The CLI dictates the canonical schema. The web app follows. Where the web app
has affordances the CLI doesn't (e.g. `/` to focus an existing search input),
those affordances reuse the CLI's binding for the same intent.

## Files touched

Rails (rails-impl agent):

- `app/javascript/controllers/keyboard_shortcuts_controller.js` — new global
  Stimulus controller. Registers the key listener, multi-key state machine (for
  `g d` / `g c` / `f s` / etc.), and dispatches to per-screen behaviors.
- `app/javascript/controllers/index.js` — registers the new controller.
- `app/views/layouts/application.html.erb` — attach the controller to `<body>`
  (or whichever element makes sense with the existing stimulus root). Add a
  top-right `[ ? ]` bracketed link near the theme switcher that opens the help
  modal.
- `app/components/keyboard_shortcuts_modal_component.rb` + `.html.erb` +
  `_spec.rb` — new ViewComponent, mirrors `ConfirmModalComponent` styling.
  Renders the bindings list grouped by section: general, navigation, list pages
  (channels/videos), detail pages, picker bulk mode, confirmation prompts.
- `app/views/shared/_keyboard_shortcuts_modal.html.erb` — slot the component
  into the layout chrome (closed by default; opened by the controller).
- Per-page Stimulus targets / data attributes added to the views that have
  screen-specific behavior:
  - `app/views/channels/_picker.html.erb` — `j` / `k` / `space` / `s` / `c` /
    `D` / `Y` / `b` / `f s` / `f c` targets.
  - `app/views/videos/index.html.erb` — same shape.
  - `app/views/channels/show.html.erb`, `app/views/videos/show.html.erb` — `v`
    (view URL), `Y` (sync), `D` (delete), `s` (star toggle).
  - `app/views/shared/_action_screen.html.erb` (the deletion / sync confirmation
    page) — `y` confirms; any other key cancels.
- `app/javascript/application.js` — if needed, hook the help-modal toggle event
  that the controller dispatches.

Specs:

- `spec/components/keyboard_shortcuts_modal_component_spec.rb` — asserts every
  binding from §"Bindings" appears in the rendered modal grouped under the right
  heading.
- `spec/system/keyboard_shortcuts_spec.rb` — drives a Capybara scenario for each
  binding using `find('body').send_keys(...)`. Asserts the resulting URL / state
  matches expectations.

CLI (cli-impl agent — out of this dispatch's lane, just a read):

- The cli-impl agent does NOT touch the CLI in this dispatch. The Rails-side
  spec READS `extras/cli/src/keys.rs` and `extras/cli/src/ui/help.rs` at the
  time of implementation to capture the canonical schema.

## Bindings (mirror the CLI verbatim — Q6 default)

The list below is the source of truth for the spec acceptance. The
implementation agent re-reads `extras/cli/src/keys.rs` and the help overlay at
the time of implementation to verify nothing drifted.

### General

- `?` — toggle help modal.
- `q` — back / close (closes overlays, navigates back from detail to list when
  no overlay is open).
- `n` — toggle dark/light theme (the same toggle the existing theme switcher
  exposes).
- `Esc` — close any overlay (help modal, action confirmation page cancel button
  equivalent).

### Navigation (`g` prefix)

- `g d` — dashboard (`/`).
- `g c` — channels (`/channels`).
- `g v` — videos (`/videos`).
- `g s` — saved views (`/saved_views`).
- `g e` — settings (`/settings`).

### Search

- `/` — focus the search input on pages that have one (search results page; the
  dashboard does not have one and the binding is a no-op there).

### List rows (channels picker, videos index, footage table)

- `j` — move selection / hover down one row.
- `k` — move selection / hover up one row.
- `space` — toggle bulk-select on the highlighted row, ONLY when bulk mode is
  on. Bulk-mode-off → silent no-op (mirrors the CLI's gated behavior).
- `b` — toggle bulk mode (open / close).
- `s` — toggle star on the highlighted row.
- `c` — toggle connected on the highlighted row (only meaningful on `/channels`;
  videos row binding is a no-op).
- `D` — delete selection (multi-row when bulk; current row when not). Routes
  through `/deletions/:type/:ids`.
- `Y` — sync selection (same shape).

### Filter chips (`f` prefix)

- `f s` — toggle the `starred` filter chip.
- `f c` — toggle the `connected` filter chip.
- `f y` — toggle the `syncing` filter chip — **dropped post-Path-A2.** The CLI
  removed this binding when the syncing column went away; the web app does not
  introduce it.

### Detail pages (channel detail, video detail)

- `v` — open the underlying URL (`channel_url` / video URL) in a new browser
  tab.
- `s` — toggle star.
- `Y` — sync.
- `D` — delete.

### Confirmation prompts (action screen pages)

- `y` — confirm (submits the form).
- Any other key — cancel (navigates to the cancel link's href).

### NOT mirrored (terminal-only affordances)

The CLI's TUI-specific bindings stay in the TUI:

- The TUI's full-screen view-mode toggles.
- TUI-specific scrolling within an overlay (the web modal scrolls natively).
- `Ctrl+C` quit (browser already has `Ctrl+W` / browser-native semantics).

## Locked design choices

- **No conflict with browser shortcuts.** `Ctrl+F` stays browser-native; the
  in-app `/` opens the app's search input. The controller checks `event.target`
  and bails out if the target is an `<input>`, `<textarea>`, or
  `[contenteditable]` — typing `j` in a search box does NOT advance the row
  selection.
- **Multi-key sequences via state machine.** The controller carries a
  `pendingPrefix` state (`null`, `"g"`, `"f"`). A prefix key sets the state,
  with a 1-second timeout that resets to `null` if no follow-up arrives. Timeout
  matches the CLI's `KeyState` shape.
- **Help modal styling = `ConfirmModalComponent` parity.** Same border, same
  monospace, same `[ close ]` bracketed link in the footer. Bindings rendered as
  `<kbd>` elements inside `[ ]` brackets to match the design system.
- **Visible affordance.** A `[ ? ]` bracketed link sits at the top-right of the
  layout chrome, near the theme switcher. Clicking it dispatches the same toggle
  the `?` keypress fires.
- **No `data-turbo-confirm`, no JS `confirm()`.** The destructive bindings (`D`
  / `Y`) navigate to the existing action confirmation page. The `y` binding ON
  that page submits the form. The destructive flow stays "page → action screen →
  confirm submit".

## Acceptance

- [ ] `keyboard_shortcuts_controller.js` is registered globally and attached to
      a stable element (most likely `<body>`).
- [ ] Pressing `?` anywhere outside an input opens the help modal; pressing `?`
      again or `Esc` closes it.
- [ ] All `g <x>` navigation bindings route to the right path (`/`, `/channels`,
      `/videos`, `/saved_views`, `/settings`).
- [ ] `n` toggles the theme using the existing theme-toggle path.
- [ ] On `/channels` (picker) and `/videos` (index): `j`/`k` move selection;
      `space` toggles bulk-select only when bulk mode is on; `b` toggles bulk
      mode; `s` toggles star; `c` toggles connected (channels only); `D` and `Y`
      route through `/deletions/...` and `/syncs/...`.
- [ ] Filter-chip bindings `f s` and `f c` toggle the chips.
- [ ] On detail pages (`/channels/:id`, `/videos/:id`), `v` opens the underlying
      URL in a new tab (`window.open(url, '_blank',     'noopener,noreferrer')`
      — never `target="_blank"` without `rel="noopener noreferrer"`);
      `s`/`Y`/`D` route correctly.
- [ ] On the action confirmation page (`/deletions/...` or `/syncs/...`), `y`
      submits the form; any other key navigates to the cancel link's href.
- [ ] The `[ ? ]` bracketed link in the layout header opens the same modal as
      pressing `?`.
- [ ] Bindings ARE NOT triggered when focus is in `<input>`, `<textarea>`, or
      `[contenteditable]`.
- [ ] No conflict with browser shortcuts (verify `Ctrl+F` still opens the
      browser's find bar; `/` does NOT also fire when in a focused input).
- [ ] System spec covers each binding category at least once.
- [ ] No `alert` / `confirm` / `prompt` introduced (verify with the existing
      hard-rule grep).
- [ ] Brakeman / RuboCop clean.

## Manual test recipe

1. `bin/dev` boots. Sign in.
2. Press `?` on the dashboard. The help modal opens, listing bindings under
   sections: general, navigation, list pages, detail pages, filter chips,
   confirmation prompts.
3. Press `Esc`. The modal closes.
4. Press `g c`. The browser navigates to `/channels`.
5. Press `j` three times. The third row in the picker is the highlighted row
   (visual indicator depends on the existing row-hover styling — the controller
   adds a class the CSS already styles).
6. Press `b`. Bulk mode opens, checkboxes appear.
7. Press `space`. The third row's checkbox toggles.
8. Press `j` then `space`. The fourth row's checkbox toggles.
9. Press `D`. Browser navigates to `/deletions/channel/<ids>`, the action
   confirmation page renders.
10. Press `y`. The form submits; the bulk-delete progress page renders.
11. Navigate back. Try `Y` on a single channel row (bulk mode off).
    Bulk-foundation routes through `/syncs/channel/<id>`.
12. Press `f s` on `/channels`. The starred filter chip toggles.
13. Open a detail page. Press `v`. The channel URL opens in a new tab.
14. Focus the search input via `/`. Type `j`. The letter `j` is typed into the
    input — no row-selection movement (focus guard).
15. Press `Ctrl+F`. The browser's native find bar opens — no in-app override.
16. Run `bundle exec rspec spec/system/keyboard_shortcuts_spec.rb` — green.

## Cross-stack scope

- Rails — **in scope.**
- `pito` CLI — **out of scope.** This spec mirrors the CLI; it does not modify
  it. The cli-impl agent does NOT participate in this dispatch.
- MCP — **out of scope.**
- Cloudflare Pages website — **out of scope.**

## Open questions

- **Q6** (from `00-phase-overview.md`) — strict mirror of the CLI keymap, or
  web-only additions allowed (`Ctrl+/` to focus search, `gg` to scroll top,
  etc.)? Default = strict mirror.

## Follow-ups created

- **CLI-side `?` help dialog parity audit.** If the Rails help modal's grouping
  ends up tighter or clearer than the CLI's current help overlay, the CLI's
  overlay can mirror back. Park as a follow-up under "next CLI dispatch touching
  the help screen".

## Decisions (locked)

- **CLI is the source of truth.** Where Rails and CLI bindings conflict, the CLI
  wins (the user has muscle memory there already). Rails-only convenience
  bindings (Q6 = web additions) are NOT in scope for this spec; if Q6 flips,
  those become a separate follow-up.
- **Visible `[ ? ]` link.** The keyboard-only audience is small; the visible
  link prevents the surface from being undiscoverable.
- **No `data-turbo-confirm` reintroduction.** The `D`/`Y` bindings go through
  the existing action confirmation page. They do NOT submit destructive forms
  inline.
