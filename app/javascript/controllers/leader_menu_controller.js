import { Controller } from "@hotwired/stimulus"

// Module-level live read of the mandatory-2FA enrollment gate.
// Mirror of the helper in `keyboard_controller.js` /
// `flat_key_controller.js`; kept duplicated rather than extracted to a
// shared module so each controller stays self-contained for
// importmap simplicity. See the layout's head comment for the full
// rationale on `<meta>`-in-head vs body-mounted signal.
function enrollTotpGateActive() {
  const meta = document.querySelector('meta[name="pito-enroll-totp-gate"]')
  return meta?.getAttribute("content") === "yes"
}

// Persistence key for the menu stack across Turbo navigations.
// Declared at module scope (not inside the class) so test code and
// any future helper can refer to the same string without divergence.
const STACK_STORAGE_KEY = "pito:leader-menu:stack"

// Leader-menu popup controller. Reads the unified keybindings schema
// embedded by the layout in `<script id="pito-keybindings">`,
// listens for SPACE on the document, and paints a small bottom-right
// popup card listing the current-menu items as `key  label` rows.
// The key glyph carries no surrounding brackets — alignment across
// rows is handled by `.leader-menu-key { min-width: 28px }` in CSS,
// so single-char (`l`, `+`) and multi-char (e.g. `␣`, `Cy`, `Nm`)
// keys still line up cleanly in the monospace face.
//
// 2026-05-18 architectural change — flat 2-key dispatch. The earlier
// nested-submenu UX (Space → `g` opens "games" submenu → `l` resolves
// games list) was dropped. The root menu now ships flat 2-key
// bindings (`Gl games list`, `Cy channels sync`, `cs calendar
// schedule`, …) resolved through the same prefix accumulator that
// powers the `page_actions` 2-key bindings (filter chips on /games,
// /settings sr/vr/da/dd/sa/sd). Direct single-key entries (`h` home,
// `S` settings, `Q` logout) fire immediately because they have no
// longer-prefix candidates. Submenus are gone schema-wide; the
// controller retains a defensive `if (hasSubmenu)` branch in
// `activate` so any future schema that DOES want a submenu still
// works, but the YAML no longer ships any.
//
// Backspace clears the pending prefix one char at a time (A1). Space
// toggles the popup (A3). Esc is NOT handled here — it falls through
// to the parent <dialog>'s native ESC handler (A4); the leader popup
// auto-closes on any other dialog's `close` event so it never
// orphan-renders above a dismissed parent. The same popup is the
// discoverable help surface — pressing the bracketed `[_]` link in
// the footer triggers `openRoot` via Stimulus `data-action`.
//
// The TUI side (`extras/cli/src/ui/leader_menu.rs`) parses the same
// `config/keybindings.yml` via `serde_yaml` and renders an
// equivalent Ratatui overlay; the two stacks stay in lockstep via
// the shared file.
//
// Bindings consumed here:
//   SPACE       toggle the root menu (open if closed, close if open)
//   Esc         NOT handled — falls through to the parent <dialog>'s
//               native ESC handler so the parent dismisses. When the
//               parent <dialog> closes the leader popup closes too
//               via the `close` event listener installed in connect().
//               When there is no parent dialog, Esc does nothing.
//   Backspace   clear the pending prefix one char at a time; if the
//               prefix is empty AND a legacy submenu is on the stack,
//               pop back one menu level.
//   <key>       append to the pending prefix; if exactly one binding
//               matches the prefix AND the prefix equals its key,
//               activate it (navigate, open submenu, emit a custom
//               event). Multi-char keys (e.g. "sr", "da") are
//               supported via the prefix accumulator.
//
// The popup IS a native `<dialog>` opened via `.showModal()` as of
// 2026-05-17 — this is the only reliable way to render above OTHER
// `<dialog>`s already opened via `.showModal()` (bundle modal,
// IGDB add-game, confirm dialogs). The browser puts every
// `.showModal()`-opened dialog in its TOP LAYER and stacks them in
// opening order; the leader popup opened LAST therefore wins. z-index
// alone cannot beat top-layer content, which is why the prior
// `<div>` + `z-index: 200` approach lost to native modals.
//
// Side-effect of `.showModal()`: the rest of the page becomes inert
// (no clicks, no focus). For a keyboard-driven leader popup this is
// fine. The backdrop is suppressed in CSS so the page stays visually
// undimmed. FB-138 (2026-05-21): the popup dismisses ONLY on [Esc]
// (Backspace stays for clearing the prefix). The previous outside-
// click dismissal was removed for parity with FB-127 dialog backdrop-
// click prevent — the leader popup is keyboard-driven and accidental
// backdrop clicks should not close it.
//
// Form-control pass-through (2026-05-11): the keypress gate that
// guards the popup-opening SPACE skips every interactive form
// control — `<input>` (all types, covering checkbox + radio),
// `<textarea>`, `<select>`, `<button>`, and `[contenteditable]`.
// Focus on any of these passes SPACE through to native form
// behaviour (literal space in a text field, toggle on a focused
// checkbox / radio, activate on a focused button). Pages like
// /settings — which are dense with form controls — were de-facto
// unreachable by the leader popup before this gate widened to
// include `<button>`; the chrome was mounted but every focused
// element on the page swallowed SPACE before it reached the
// controller. See `isEditableTarget`.
//
// Dismiss-on-navigate (2026-05-10): the popup ALSO closes on every
// `turbo:visit` event — any Turbo navigation start, whether triggered
// by a leader-menu action, a click on a link / button anywhere on
// the page, or a form submission. This guarantees the popup never
// lingers after the user has begun navigating somewhere else, even
// after FB-138 removed the outside-click dismissal — any link/button
// click that DOES trigger navigation still closes via this path. The
// `turbo:visit` listener
// also clears the persisted menu stack from `sessionStorage` so the
// popup does NOT silently rehydrate on the destination page. The TUI
// side already closes on every resolved keybinding action via the
// `Resolved` enum; the web side now matches.
//
// Item shape (from the schema):
//   { key: "h", label: "home", action: { type: "navigate", path: "/" } }
//   { key: "C", label: "channels", submenu: "channels" }
//
// Action types recognized:
//   navigate         { path: "/..." }            → Turbo.visit(path) when
//     available, falling back to window.location.assign(path). Turbo
//     keeps the popup mounted across the page swap (the popup lives
//     on `<body>`, which Turbo preserves as a permanent element via
//     `data-turbo-permanent`).
//   open / today / logout / etc. → dispatched as a
//     "leader-menu:action" CustomEvent on `document`; listeners
//     wired by other controllers (the notifications modal, the
//     keyboard controller's logout flow, etc.) react. Unknown
//     action types fall through and emit the same event so future
//     handlers can plug in without touching this file.
//
// Schema shape (2026-05-18 flat 2-key dispatch): the root menu is a
// single flat list of items, each carrying a `key` (one or two chars)
// and an `action`. Multi-char keys (e.g. `Cy`, `Gl`, `cs`, `c+`)
// resolve through the prefix accumulator the same way the
// `page_actions` 2-key bindings do. No `submenu` field appears on
// any shipped schema row — the nested-submenu UX was dropped per
// the 2026-05-18 architectural change.
//
// The controller still defensively handles a hypothetical row with
// a `submenu` field (preferring `submenu` and ignoring any `action`)
// so a future schema can opt back in without a code change here.
// The inline-submenu mechanism on `page_actions` items
// (`action: { type: submenu, items: [...] }`) is also preserved
// untouched — only the root nested-submenu flow is gone.
//
// Implementation note: all popup contents are built via DOM
// construction (`createElement` + `textContent`) rather than
// `innerHTML`, so user-visible strings (menu names, item labels)
// pass through the browser's text-encoding path with no HTML
// interpretation. The schema itself is statically defined in
// `config/keybindings.yml` and contains no user input today, but
// building safely keeps the surface defensive in case a future
// schema gains user-controlled values.
export default class extends Controller {
  static targets = ["popup"]

  connect() {
    // 2026-05-19 — schema parsing moved to a lazy `get schema()` getter
    // so a stale parse cached at connect time can never strand the
    // controller. Previously the controller parsed the schema once
    // here and stored it on `this.schema`; if Turbo Drive's body swap
    // timing meant the `<script id="pito-keybindings">` tag wasn't
    // findable at the exact moment Stimulus reconnected (despite the
    // tag being in the new DOM), the controller bailed via the
    // early-return below and registered NO listeners — SPACE leader
    // went dead, and the `flat-key:open-leader-with-prefix` listener
    // never bound either (so flat `g` / `q` compact-menu opens never
    // landed). The fix:
    //   1. Schema parsing is now in `get schema()` (lazy per-access
    //      `document.getElementById` read with JSON.parse). Every
    //      schema reader (`onKeydown`, `menuByName`, `resolvePageActions`,
    //      etc.) goes through the getter, so a missing tag at
    //      connect time no longer permanently disables the controller
    //      — the next keystroke re-tries.
    //   2. Listener registration below is unconditional. Even if the
    //      schema parse fails on the FIRST keystroke, the listener is
    //      still installed and will succeed on a later keystroke once
    //      the tag is in the DOM. Same defensive shape as
    //      `flat_key_controller`.
    //   3. The `<script id="pito-keybindings">` tag was moved from
    //      body-bottom to `<head>` (see layout) so Turbo's head merge
    //      via `isEqualNode` keeps it intact across nav — the lazy
    //      read always finds a populated tag.
    this.menuStack = []
    // Inline submenus declared inside a page-action `action: { type:
    // submenu, items: [...] }` entry. Pushed onto `menuStack` by a
    // synthetic name (e.g. `inline:filter:f`) and resolved by
    // `menuByName` before falling through to `schema.menus`. Used by
    // the `f filter` submenu on /games (toggle filter chips without
    // leaving the popup); the schema gets a sub-menu without minting
    // a new top-level entry under `menus:`.
    this.inlineMenus = {}
    // 2-key sequence support (A1). Holds the characters typed since
    // the popup opened (or since the last full activation / reset).
    // A binding fires when `pendingPrefix` equals its key exactly AND
    // no other binding has the prefix as a strict subset. Reset on:
    // successful activation, no-match keystroke, 1500 ms inactivity,
    // backspace-to-empty, popup close.
    this.pendingPrefix = ""
    this.prefixTimer = null
    // Phase C (2026-05-17): when the user types a prefix that matches
    // both an exact binding AND longer candidates (e.g. `d` matches
    // `d dark mode` AND `da` / `dd` on /settings), stash the exact
    // match here so the inactivity timer can fire it on expiry. Reset
    // by `resetPrefix`, `close`, and every keystroke.
    this.pendingExactMatch = null
    // Compact-mode flag (2026-05-19). Flipped to `true` whenever the
    // popup opens via the flat-key `open_leader_with_prefix` action
    // (pressing `g` / `q` on the neutral page chrome). Compact mode
    // hides the local section so the popup renders ONLY the prefix-
    // filtered navigation rows — the user is mid-flow on a 2-letter
    // root binding, not browsing page surface keys. Reset on every
    // popup close. Mirrored on the popup `<dialog>` as
    // `data-compact="true"` so CSS can hide the local section.
    this.compactMode = false
    // Compact-prefix floor (2026-05-19). Stores the seed prefix passed
    // by the flat-key surface (`g` / `q`) so the popup keeps filtering
    // navigation rows by that prefix even after the inactivity timer
    // resets `pendingPrefix` back below the floor. Without this floor
    // the popup would show ALL rows (qQ leaks into a `g` compact view)
    // after a 1500ms idle, and a `gg` dead-end would not dismiss
    // because the second `g` would re-set `pendingPrefix` to `g` (not
    // `gg`). Reset on every popup close.
    this.compactPrefix = ""
    // FB-147 (2026-05-21) — track the current vim-style mode so SPACE
    // (and every other leader key) bails out while INSERT is active.
    // The `tui-cursor` controller owns the mode state machine and
    // broadcasts every transition via the `tui:mode-changed` event
    // (see app/javascript/controllers/tui_cursor_controller.js). In
    // INSERT mode, SPACE is owned by the cursor controller — it
    // toggles the focused row's checkbox. Without this guard, focused
    // input loses keystrokes (SPACE doesn't insert a space) AND the
    // leader popup spawns over notifications/security rows, surprising
    // the user.
    this.insertMode = false
    this.boundModeChanged = this.onModeChanged.bind(this)
    this.boundKeydown = this.onKeydown.bind(this)
    this.boundTurboVisit = this.onTurboVisit.bind(this)
    // 2026-05-19 — the `flat-key` controller fires this event when a
    // flat (leader-less) `g` / `q` keystroke lands on the neutral
    // page chrome. The handler opens the popup + flips compact mode
    // + seeds the prefix so the popup renders the prefix-filtered
    // navigation rows immediately.
    this.boundFlatKeyOpen = this.onFlatKeyOpenWithPrefix.bind(this)
    // A4: when any <dialog> on the page closes, the leader popup
    // closes alongside it so an orphan popup never lingers above a
    // dismissed parent dialog. Esc on the leader popup falls through
    // to the parent <dialog> (we install no Esc handler here per A4);
    // the parent's native Esc handling fires its `close` event; this
    // listener catches every close (parent OR leader) and ensures the
    // leader closes whenever ANOTHER dialog does. Self-close is a
    // no-op via the `isOpen()` guard inside `close()`.
    this.boundDialogClose = this.onDialogClose.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    document.addEventListener("tui:mode-changed", this.boundModeChanged)
    // `close` does not bubble on <dialog>; capture phase catches every
    // dialog close anywhere in the document.
    document.addEventListener("close", this.boundDialogClose, true)
    // Close the popup the moment any Turbo navigation begins. After
    // FB-138 removed the outside-click dismissal, this is the primary
    // path that ensures the popup never lingers when the user clicks
    // a link/button that triggers navigation. Also catches programmatic
    // navigations (Turbo.visit from leader-menu's own action handler,
    // form submits, prefetch-triggered visits).
    document.addEventListener("turbo:visit", this.boundTurboVisit)
    document.addEventListener("flat-key:open-leader-with-prefix", this.boundFlatKeyOpen)
    // NOTE — DO NOT short-circuit `connect()` on `!hasPopupTarget`.
    // The popup `<div id="leader-menu-popup" data-turbo-permanent>`
    // lives at the END of `<body>`. On a Turbo Drive navigation the
    // permanent-element preservation flow (`Bardo.preservingPermanentElements`
    // in turbo.js) runs in this order:
    //
    //   1. `enter()` — in the NEW body (still off-document), the new
    //      popup div is REPLACED with a `<meta name="turbo-permanent-placeholder">`.
    //   2. `activateNewBody()` + `assignNewBody()` — `document.body.replaceWith(newBody)`
    //      mounts the new body into the document. Stimulus's mutation
    //      observer fires immediately and connects every controller
    //      declared on the new body (including this one). At THIS
    //      moment `hasPopupTarget` is FALSE — the popup div lives
    //      neither in the old body (just removed) nor in the new
    //      body (replaced by the placeholder meta).
    //   3. `leave()` — Turbo finds the placeholder meta in the now-
    //      current body and replaces it with the OLD preserved popup
    //      element. From this point on `hasPopupTarget` returns TRUE.
    //
    // The old `if (!this.hasPopupTarget) return` guard meant the
    // controller bailed at step 2 — no keydown listener registered,
    // no turbo:visit listener registered — and stayed dead even after
    // step 3 re-attached the popup. The SPACE leader broke on every
    // page after the first Turbo Drive navigation. The fix is to
    // register listeners unconditionally and check `hasPopupTarget`
    // LAZILY inside the action handlers (`isOpen`, `openMenu`,
    // `close`, `render`, `rehydrate`) — all of which already gate on
    // `hasPopupTarget` before touching the popup. On a chrome-stripped
    // surface (auth pages with `content_for(:hide_chrome)` — though
    // those pages don't even mount the `leader-menu` controller today
    // because `<body data-controller>` is gone), the listeners
    // silently no-op because every action path bails before touching
    // a missing target.
    //
    // Rehydrate any stack persisted before the last Turbo navigation.
    // Historically a single keystroke could navigate AND drill, which
    // required carrying the popup across the page swap. After the
    // 2026-05-10 revert plus dismiss-on-navigate, the popup ALWAYS
    // closes on navigation, so `rehydrate` is now a no-op in practice
    // (the `turbo:visit` handler clears sessionStorage). It stays as
    // a defensive guard against a future schema entry that legitimately
    // wants to keep the popup open across pages.
    this.rehydrate()
  }

  disconnect() {
    if (this.boundKeydown) document.removeEventListener("keydown", this.boundKeydown)
    if (this.boundModeChanged) document.removeEventListener("tui:mode-changed", this.boundModeChanged)
    if (this.boundTurboVisit) document.removeEventListener("turbo:visit", this.boundTurboVisit)
    if (this.boundDialogClose) document.removeEventListener("close", this.boundDialogClose, true)
    if (this.boundFlatKeyOpen) document.removeEventListener("flat-key:open-leader-with-prefix", this.boundFlatKeyOpen)
    if (this.prefixTimer) {
      clearTimeout(this.prefixTimer)
      this.prefixTimer = null
    }
  }

  // Public entry point wired to the footer `[_]` link via
  // `data-action="click->leader-menu#openRoot"`. Toggles: clicking
  // while open closes the popup (matches LazyVim's leader-double-tap
  // behavior).
  openRoot(event) {
    if (event) event.preventDefault()
    if (this.isOpen()) {
      this.close()
    } else {
      this.openMenu("root")
    }
  }

  // Public close. Wired to popup `[close]` link if any.
  //
  // The popup is a native `<dialog>` opened via `.showModal()`
  // (2026-05-17), so closing means calling `.close()` to remove it
  // from the browser's top layer. Idempotent — safe to call when the
  // dialog is already closed.
  close(event) {
    if (event) event.preventDefault()
    this.menuStack = []
    // Inline submenus are scoped to the open popup — wipe on close so
    // a stale `inline:*` entry can't shadow a future top-level menu
    // accidentally named the same. The map rebuilds on demand when
    // `activate()` next encounters a `type: submenu` action.
    this.inlineMenus = {}
    this.resetPrefix()
    this.persistStack()
    if (this.hasPopupTarget) {
      if (this.popupTarget.open) this.popupTarget.close()
      while (this.popupTarget.firstChild) this.popupTarget.removeChild(this.popupTarget.firstChild)
      // Drop the compact-mode marker so the next popup open starts
      // in full mode unless re-flipped by `onFlatKeyOpenWithPrefix`.
      this.popupTarget.removeAttribute("data-compact")
    }
    this.compactMode = false
    this.compactPrefix = ""
    // Force pendingPrefix back to empty AFTER the compact-mode flags
    // are cleared. The earlier `resetPrefix()` call (line above the
    // `compactMode = false` flip) keeps the floor when still in
    // compact mode; clearing it here ensures the next popup open
    // starts from a clean accumulator regardless of how this popup
    // closed.
    this.pendingPrefix = ""
  }

  isOpen() {
    // Native `<dialog>` exposes `open` as a live attribute that
    // flips with `.showModal()` / `.close()` — read it directly
    // instead of the prior `hidden` flag.
    return this.hasPopupTarget && this.popupTarget.open === true
  }

  // 2026-05-19 — lazy schema getter. Re-reads
  // `<script id="pito-keybindings">` from the DOM on every access
  // and JSON.parses it. Replaces the prior connect-time cache on
  // `this.schema`. The tag lives in `<head>` (moved 2026-05-19) so
  // Turbo Drive's head-merge `isEqualNode` diff keeps it intact
  // across navigations — every lazy read finds the live JSON. Returns
  // `null` when the tag is missing OR parse fails so callers can
  // bail uniformly (`if (!schema) return`). The per-keystroke cost
  // is O(items) — trivial for the < 20-row shipped schema.
  get schema() {
    const node = document.getElementById("pito-keybindings")
    if (!node) return null
    try {
      return JSON.parse(node.textContent || "{}")
    } catch (_err) {
      return null
    }
  }

  // ---- key handling ----------------------------------------------

  // FB-147 (2026-05-21) — react to NORMAL ↔ INSERT transitions broadcast
  // by the `tui-cursor` controller. We never SPAWN the popup while
  // INSERT mode is active; if the popup is already open when mode
  // flips to INSERT (the user hit `i` while leader was up), close it
  // so it can't gobble keystrokes the focused input expects.
  onModeChanged(event) {
    const mode = event && event.detail && event.detail.mode
    if (mode === "insert") {
      this.insertMode = true
      if (this.isOpen()) this.close()
    } else {
      this.insertMode = false
    }
  }

  onKeydown(event) {
    if (!this.schema) return
    // FB-147 (2026-05-21) — INSERT mode owns the keyboard. SPACE in
    // INSERT is the cursor controller's "toggle focused row's
    // checkbox" hotkey (see tui_cursor_controller.js handleKey); every
    // other printable key needs to reach the focused input/textarea.
    // The popup must never spawn or accumulate prefix keystrokes here.
    // Esc is handled by the cursor controller (blur + return to NORMAL),
    // not us.
    if (this.insertMode) return
    // Mandatory-2FA enrollment gate. When the authenticated user has
    // not configured TOTP, the layout renders
    // `<meta name="pito-enroll-totp-gate" content="yes">` in `<head>`
    // and the SPACE leader is inert — opening the leader menu would
    // expose navigation actions (home, channels, videos, etc.) that
    // the server-side gate already forbids. The enrollment form's
    // own keys (typing the 6-digit code, Tab between fields, Enter
    // to submit) keep working because they fire on a focused
    // `<input>` via native browser behaviour. Released the moment
    // enrollment completes (next page render flips the meta content
    // back to `"no"`).
    //
    // Why a `<meta>` in `<head>` rather than a body data-attribute
    // or inline body `<script>`: see the layout comment next to the
    // meta tag — both body-mounted signals went stale across Turbo
    // navigations.
    if (enrollTotpGateActive()) return
    // Never swallow keys while focus is on a form-entry surface:
    // <input> (every type, including checkbox / radio), <textarea>,
    // <select>, <button>, and `[contenteditable]`. See
    // `isEditableTarget` below for the full rationale. This is what
    // makes /settings (and any other page packed with form controls)
    // usable — pressing SPACE on a focused [update] button must
    // submit the form, not open the popup.
    if (this.isEditableTarget(event.target)) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (this.isOpen()) {
      // A4: Esc is intentionally NOT handled here. Let it fall through
      // to the parent <dialog>'s native ESC handler. If a parent
      // <dialog> dismisses, its `close` event triggers `onDialogClose`
      // which closes this leader popup. If no parent dialog is open,
      // Esc is a no-op (leader stays open; Space closes it per A3).
      if (event.key === "Escape") return

      if (event.key === "Backspace") {
        event.preventDefault()
        // A1: Backspace pops the last char from the pending prefix
        // first. Only when the prefix is already empty do we fall back
        // to the legacy submenu pop-back (so the `f filter` submenu
        // still navigates back to the root menu on Backspace).
        if (this.pendingPrefix.length > 0) {
          this.pendingPrefix = this.pendingPrefix.slice(0, -1)
          // 2026-05-19 — compact mode close-on-empty. The popup was
          // opened via a flat-key prefix (`g` / `q`); when the user
          // clears the prefix back to empty there is no meaningful
          // fallback to "full leader view" — that requires a SPACE
          // press. Close the popup so the user can hit SPACE next
          // for the unfiltered view.
          if (this.compactMode && this.pendingPrefix.length === 0) {
            this.close()
            return
          }
          this.armPrefixTimer()
          this.repaint()
        } else {
          this.popMenu()
        }
        return
      }
      if (event.key === " ") {
        // A3: Space TOGGLES — when open, Space closes.
        event.preventDefault()
        this.close()
        return
      }
      // A1: prefix accumulator. Append the keystroke and route through
      // `handlePrefixKey`. Only single printable keys participate;
      // modifier-bare arrow keys / Tab / etc. are ignored so they
      // don't pollute the prefix.
      if (event.key.length === 1) {
        event.preventDefault()
        this.handlePrefixKey(event.key)
      }
      return
    }

    // Popup closed: only SPACE opens it. The `?` and `g`/`f` prefix
    // bindings remain owned by `keyboard_controller.js`.
    if (event.key === " ") {
      // SPACE in a list-row context is bound by the keyboard
      // controller to toggle selection. Defer to it: if any
      // `[data-keyboard-row].keyboard-highlight` is on the page,
      // the leader popup should NOT open. Otherwise, open root.
      if (document.querySelector("[data-keyboard-row].keyboard-highlight")) return
      event.preventDefault()
      this.openMenu("root")
    }
  }

  // A1: 2-key sequence support.
  //
  // Append `key` to the pending prefix, then look at the items in the
  // current menu (including page actions when at root) that START with
  // the prefix:
  //   * zero matches → reset prefix (sequence dead-ends silently),
  //   * exact match AND no longer prefix candidate → fire it,
  //   * exact match AND longer candidates exist → ARM the timer
  //     with the exact match recorded; the timer fires the exact
  //     match on inactivity, or the next keystroke supersedes it,
  //   * strict-prefix match only (no exact) → wait for next key,
  //   * 1500 ms inactivity → reset prefix (firing the recorded
  //     exact-match candidate if one was stashed).
  //
  // Phase C extension (2026-05-17): the prior code reset the prefix
  // on timer expiry without firing anything. /settings introduced
  // `d` (dark mode) alongside `da` / `dd` — a classic vim-style
  // prefix conflict. Pressing `d` alone must still fire dark mode
  // (with a ~1500 ms grace period for the follow-up keystroke).
  // The recorded exact-match candidate (`pendingExactMatch`) is
  // consumed by `armPrefixTimer`'s expiry callback or cleared by the
  // next keystroke / activation / reset.
  //
  // The legacy single-char submenu path (`f` opens an inline submenu)
  // still works because `f` is itself a binding key — once the prefix
  // equals `f` and there is no longer `f*` candidate, we activate it.
  handlePrefixKey(key) {
    this.pendingPrefix += key
    const candidates = this.candidatesForPrefix(this.pendingPrefix)

    if (candidates.length === 0) {
      // Dead-end. In compact mode (popup opened via the flat-key `g`
      // / `q` prefix), the user has no meaningful fallback to "full
      // leader view" — that requires a SPACE press. Close the popup
      // so the next SPACE opens the unfiltered menu. Example: hitting
      // `g` opens compact gC/gG/gS; hitting `g` again accumulates the
      // prefix to `gg` which matches no row → dismiss. Non-compact
      // (SPACE-opened) flow keeps the prior reset-and-repaint
      // semantic so the user can keep typing.
      if (this.compactMode) {
        this.close()
        return
      }
      this.resetPrefix()
      this.repaint()
      return
    }

    const exact = candidates.find((c) => c.key === this.pendingPrefix)
    const longer = candidates.find((c) => c.key !== this.pendingPrefix)

    if (exact && !longer) {
      // Unique exact match — fire and reset.
      const itemToFire = exact
      this.resetPrefix()
      this.activate(itemToFire)
      return
    }

    // Stash the exact match (if any) so the timer-expiry path can
    // fire it on inactivity. When `longer` also exists, the user has
    // ~1500 ms to disambiguate by pressing another key; otherwise
    // the exact match fires. When only longer candidates exist
    // (`exact === undefined`), the stash is cleared and timer expiry
    // resets silently.
    this.pendingExactMatch = exact || null

    // Either multiple matches OR a strict-prefix match exists; wait
    // for the next keystroke and repaint to dim non-matching rows.
    this.armPrefixTimer()
    this.repaint()
  }

  // Return the items in the active scope whose `key` starts with the
  // given prefix. At root the page-actions list is searched first so
  // a page-action can shadow a same-prefix menu item (intentional —
  // page actions are page-scoped overrides).
  //
  // 2026-05-18 — navigation is ALWAYS dispatchable, including when a
  // modal is open. The earlier modal-context short-circuit (which
  // suppressed nav items both visually and in dispatch) created a bug
  // where pressing Space inside a modal hid the navigation section
  // entirely. Per locked direction, modal_actions PREPEND the page
  // actions list while the root navigation menu remains visible and
  // dispatchable alongside. Pressing `h` inside a modal navigates home
  // (the Turbo visit closes the modal naturally as the page swaps).
  candidatesForPrefix(prefix) {
    if (prefix.length === 0) return []
    const name = this.menuStack[this.menuStack.length - 1]
    const out = []
    if (name === "root") {
      this.resolvePageActions().forEach((item) => {
        if (item && item.key && typeof item.key === "string" && item.key.startsWith(prefix)) {
          out.push(item)
        }
      })
    }
    const menu = this.menuByName(name)
    if (menu) {
      ;(menu.items || []).forEach((item) => {
        if (item && item.key && typeof item.key === "string" && item.key.startsWith(prefix)) {
          out.push(item)
        }
      })
    }
    return out
  }

  // 1500 ms inactivity → reset the pending prefix. Re-armed on every
  // keystroke that does not immediately fire / dead-end. The expiry
  // also repaints so dim styling clears on its own.
  //
  // Phase C (2026-05-17): when an exact match is stashed in
  // `pendingExactMatch` (the case where the user typed a prefix that
  // is both an exact binding AND a prefix of longer ones), the
  // expiry fires the stashed match — that's how `d` (dark mode) on
  // /settings still works despite `da` / `dd` sharing the `d` prefix.
  // The stash is consumed via a local snapshot so `resetPrefix`'s
  // teardown doesn't clear it before `activate` runs.
  armPrefixTimer() {
    if (this.prefixTimer) clearTimeout(this.prefixTimer)
    this.prefixTimer = setTimeout(() => {
      const stashed = this.pendingExactMatch
      this.resetPrefix()
      if (stashed) {
        this.activate(stashed)
      } else {
        this.repaint()
      }
    }, 1500)
  }

  resetPrefix() {
    // In compact mode the seed prefix is the floor — `pendingPrefix`
    // never falls below it via the inactivity timer or a no-longer-
    // matching keystroke. Keeping the floor here means a subsequent
    // `g` press after a 1500ms idle accumulates to `gg` (dead-end →
    // close) rather than to a fresh single `g`.
    this.pendingPrefix = this.compactMode && this.compactPrefix ? this.compactPrefix : ""
    this.pendingExactMatch = null
    if (this.prefixTimer) {
      clearTimeout(this.prefixTimer)
      this.prefixTimer = null
    }
  }

  // Re-render the currently active menu. Cheap wrapper around `render`
  // so the prefix-accumulator code can refresh dim/highlight rows
  // without duplicating the lookup.
  repaint() {
    const name = this.menuStack[this.menuStack.length - 1]
    if (!name) return
    const menu = this.menuByName(name)
    if (menu) this.render(menu, name)
  }

  // A4: when ANY <dialog> on the page closes, ensure the leader popup
  // closes alongside it. Bundle-modal Esc, IGDB-modal Esc, confirm-
  // dialog Esc all fire a native `close` event we hook here. Closing
  // the leader popup itself also fires `close` (since it IS a dialog),
  // so we no-op if the event target is the leader popup itself — that
  // path is already taking care of teardown.
  onDialogClose(event) {
    if (!this.hasPopupTarget) return
    if (event.target === this.popupTarget) return
    if (!this.isOpen()) return
    this.close()
  }

  // Close on every Turbo navigation start. The popup MUST NOT survive
  // a page transition — whether the user clicked a link, submitted a
  // form, or pressed a leader-menu navigate key. `close()` is safe to
  // call when the popup is already hidden (it's a no-op aside from a
  // sessionStorage clear), so we don't guard on `isOpen()` here: the
  // clear also wipes any rehydratable state so the new page boots
  // without the popup mounted.
  onTurboVisit(_event) {
    this.close()
  }

  // 2026-05-19 — flat-key compact open. The `flat-key` Stimulus
  // controller fires `flat-key:open-leader-with-prefix` when the user
  // presses a leader-less prefix key (`g` / `q` per
  // `config/keybindings.yml#flat`). The handler:
  //   1. Opens the root menu the same way SPACE does (`openMenu("root")`).
  //   2. Flips `compactMode` on so backspace-to-empty closes the popup
  //      instead of pop-back. Mirrored on the popup `<dialog>` as
  //      `data-compact="true"` so the CSS rule
  //      `.leader-menu-popup[data-compact="true"] .leader-menu-page-actions`
  //      (also targets the paired hairline) hides the local section
  //      — the user is mid-flow on a 2-letter root binding, not
  //      browsing page surface keys.
  //   3. Seeds the prefix accumulator by routing the prefix char(s)
  //      through `handlePrefixKey` so dim/match styling + the timer
  //      arm exactly as if the user typed them inside the popup.
  //
  // No-op when the popup is already open (the user is mid-flow on
  // the leader popup; the flat-key surface is gated to closed-only
  // anyway via the open-dialog guard in `flat_key_controller`) or
  // when the prefix detail is missing / non-string.
  onFlatKeyOpenWithPrefix(event) {
    if (this.isOpen()) return
    const prefix = event && event.detail && typeof event.detail.prefix === "string"
      ? event.detail.prefix
      : ""
    if (prefix.length === 0) return
    this.compactMode = true
    // Record the seed prefix as the compact floor before the first
    // render. `buildItemRow` / `buildGridCell` use this floor to hide
    // rows that don't start with it, independent of the live
    // `pendingPrefix` accumulator — so qQ stays hidden across the
    // 1500ms inactivity-timer reset and a second `g` keystroke
    // accumulates to a true `gg` dead-end that dismisses the popup.
    this.compactPrefix = prefix
    this.openMenu("root")
    if (this.hasPopupTarget) {
      this.popupTarget.setAttribute("data-compact", "true")
    }
    // Route every char through the accumulator so multi-char flat
    // prefixes (none today, but defensive for future schemas) seed
    // correctly. Single-char prefixes — the only shape today — also
    // work because `handlePrefixKey` arms the timer + repaints when
    // longer candidates exist (e.g. `g` has `gC` / `gG` / `gS`).
    for (const ch of prefix) {
      this.handlePrefixKey(ch)
    }
  }

  // ---- menu rendering --------------------------------------------

  openMenu(name) {
    const menu = this.menuByName(name)
    if (!menu) return
    this.menuStack.push(name)
    this.persistStack()
    this.render(menu, name)
    if (this.hasPopupTarget) this.showPopup()
  }

  // Place the popup in the browser top layer via `.showModal()` so
  // it renders ABOVE any other `<dialog>` already open via the same
  // call (bundle modal, IGDB add-game, confirm dialogs). The browser
  // stacks top-layer elements in opening order — calling
  // `.showModal()` after another dialog opened wins. z-index alone
  // can't beat top-layer content, which is why the prior `<div>` +
  // `z-index: 200` approach lost to native modals.
  //
  // Guards against double-open (Firefox throws an `InvalidStateError`
  // if `.showModal()` is called on an already-open dialog).
  showPopup() {
    if (!this.hasPopupTarget) return
    if (this.popupTarget.open) return
    if (typeof this.popupTarget.showModal === "function") {
      this.popupTarget.showModal()
    }
  }

  popMenu() {
    this.menuStack.pop()
    if (this.menuStack.length === 0) {
      this.close()
      return
    }
    this.persistStack()
    const name = this.menuStack[this.menuStack.length - 1]
    const menu = this.menuByName(name)
    if (menu) this.render(menu, name)
  }

  menuByName(name) {
    // Inline submenus (synthetic names like `inline:filter:f`,
    // declared on a page-action `action: { type: submenu, items: [] }`
    // entry) win over the static schema. See `inlineMenus` doc on
    // `connect()` for the why.
    if (this.inlineMenus && Object.prototype.hasOwnProperty.call(this.inlineMenus, name)) {
      return this.inlineMenus[name]
    }
    if (!this.schema || !this.schema.menus) return null
    return this.schema.menus[name] || null
  }

  // Resolve a SINGLE-CHAR keypress against the active menu. SUPERSEDED
  // by the prefix-accumulator pipeline (`handlePrefixKey` +
  // `candidatesForPrefix`) for live dispatch — `onKeydown` no longer
  // calls this. Retained as a utility helper for any future caller
  // (e.g. a programmatic "fire key X" hook) that wants exact single-
  // char lookup with the same page-actions-shadow-menu semantics. Safe
  // to delete if no consumer surfaces.
  //
  // Search order at root: page-actions FIRST, then menu items. This
  // matches the visual order in the popup and means a page-action
  // can shadow a same-letter menu item (intentional — page actions
  // are page-scoped overrides).
  findItem(key) {
    const name = this.menuStack[this.menuStack.length - 1]
    if (name === "root") {
      const pageHit = this.resolvePageActions().find((item) => item.key && item.key === key)
      if (pageHit) return pageHit
    }
    const menu = this.menuByName(name)
    if (!menu) return null
    // Divider entries (`{ divider: true }`) carry no `key` — skip them
    // during dispatch so a divider can never absorb a keystroke. The
    // renderer paints them as visual hairlines only (see `render` /
    // `buildItemRow`).
    return (menu.items || []).find((item) => item.key && item.key === key) || null
  }

  activate(item) {
    const action = item.action
    const hasAction = action && action.type
    const hasSubmenu = !!item.submenu

    // Defensive submenu branch (2026-05-18). The shipped schema no
    // longer carries `submenu` fields on any root row — the
    // nested-submenu UX was replaced by flat 2-key dispatch. The
    // branch stays here as a safety net so any future schema entry
    // that opts back into a submenu still works. When both `submenu`
    // and `action` appear on the same row, submenu wins and the
    // action is silently ignored.
    if (hasSubmenu) {
      this.openMenu(item.submenu)
      return
    }

    // Inline submenu — page-action item whose action declares its
    // own nested `items` list (e.g. `f filter` on /games). Synthesize
    // a name, stash the menu in `inlineMenus`, and drill in via the
    // same `openMenu` path. Keeping the inline name namespaced under
    // `inline:` avoids collisions with any future top-level schema
    // menu of the same name.
    if (hasAction && action.type === "submenu" && Array.isArray(action.items)) {
      const inlineName = `inline:${item.key}:${item.label || ""}`
      this.inlineMenus[inlineName] = { items: action.items }
      this.openMenu(inlineName)
      return
    }

    if (hasAction) {
      this.fireAction(item, action, { closePopup: true })
    }
  }

  // Run the action side-effect and optionally close the popup. The
  // popup always closes BEFORE the side-effect runs so a navigate /
  // modal-open never races against an already-mounted popup.
  //
  // Dispatch table (2026-05-19 — `theme_toggle` removed alongside the
  // single-theme cleanup; the leader popup no longer toggles dark/light):
  //   navigate     → Turbo.visit(action.path) / window.location.assign
  //   page_sync    → POST to <body data-page-sync-url>
  //   page_delete  → showModal() on <dialog id={data-page-delete-modal-id}>
  //   open_modal   → opens the layout `global-search-modal` <dialog>
  //                  when modal_id === "search_placeholder" (the YAML
  //                  token reserved by `page_actions:` `/` for the
  //                  global search modal); otherwise emits the
  //                  CustomEvent fallback so future modal_ids can wire
  //                  listeners.
  //   anything else → "leader-menu:action" CustomEvent on `document`;
  //                   listeners (notifications modal, etc.) react.
  //
  // History: the action-key handlers (page_sync / page_delete /
  // openGlobalSearch) previously lived on `keyboard_controller` and
  // were reached via `window.Stimulus.getControllerForElementAndIdentifier(
  // <body>, "keyboard")`. That cross-controller dispatch was fragile —
  // when the lookup returned null (Stimulus not yet wired, lookup
  // timing, future layout change), the guarded `if (... && kb)`
  // branches silently fell through and the action no-op'd with no
  // console error. The handlers now live inline on this controller so
  // the dispatch is a direct method call with no lookup. The methods
  // on `keyboard_controller` remain (unused) as a deprecated holdover —
  // a follow-up sweep can delete them once we're sure no other caller
  // resurfaces.
  fireAction(item, action, { closePopup }) {
    if (closePopup) this.close()

    if (action.type === "navigate" && action.path) {
      this.navigateTo(action.path)
      return
    }
    if (action.type === "page_sync") {
      this.pageSync()
      return
    }
    if (action.type === "page_delete") {
      this.pageDelete()
      return
    }
    if (action.type === "page_add_bundle") {
      this.pageAddBundle()
      return
    }
    if (action.type === "open_modal" && action.modal_id === "search_placeholder") {
      this.openGlobalSearch()
      return
    }
    // Generic `open_modal { modal_id: <dom-id> }` — resolves the
    // `<dialog id={modal_id}>` and opens it. Added 2026-05-19 for the
    // `?` keybind in `menus.root` (about-modal). Matches the flat
    // controller's `open_modal` handler so leader + flat dispatch the
    // same shape consistently.
    if (action.type === "open_modal" && action.modal_id) {
      this.openModalById(action.modal_id)
      return
    }
    if (action.type === "toggle_filter_chip" && action.token) {
      this.toggleFilterChip(action.token)
      return
    }
    if (action.type === "logout") {
      this.performLogout()
      return
    }
    if (action.type === "trigger_inline_edit" && action.target) {
      this.triggerInlineEdit(action.target)
      return
    }
    if (action.type === "submit_confirm_modal") {
      this.submitConfirmModal()
      return
    }
    if (action.type === "open_modal_by_id" && action.target) {
      this.openModalById(action.target)
      return
    }
    if (action.type === "open_revoke_unused_modal" && action.target) {
      this.openRevokeUnusedModal(action.target)
      return
    }
    if (action.type === "toggle_setting" && action.target) {
      this.toggleSetting(action.target)
      return
    }

    document.dispatchEvent(
      new CustomEvent("leader-menu:action", {
        detail: { item: item, action: action }
      })
    )
  }

  // ---- action-key handlers (inlined from keyboard_controller) ----

  // `page_sync` — locate the page's breadcrumb sync trigger by the
  // `[data-page-action="sync"]` hook and synthesize a click on it.
  // 2026-05-18 — switched from the prior `<body data-page-sync-url>` +
  // direct `fetch()` POST. The hook-based dispatch is simpler and
  // delegates the actual POST to the breadcrumb's existing surface
  // (a `button_to`-generated `<button>` inside a form, or a
  // controller-bound anchor). Clicking the button submits the form,
  // which goes through the standard `data-turbo="false"` POST path
  // and lands the server-side redirect — same surface the user gets
  // from a manual breadcrumb click. No-op when the hook isn't on the
  // page (e.g. on a non-show surface, or before the breadcrumb-action
  // block has been rendered).
  pageSync() {
    const el = document.querySelector('[data-page-action="sync"]')
    if (el && typeof el.click === "function") el.click()
  }

  // `page_delete` — locate the page's breadcrumb delete trigger by the
  // `[data-page-action="delete"]` hook and synthesize a click on it.
  // 2026-05-18 — switched from the prior `<body data-page-delete-modal-id>`
  // lookup + direct `showModal()`. The hook-based dispatch fires the
  // breadcrumb anchor's own `click->modal-trigger#open` Stimulus
  // action, so the modal-open path stays single-sourced through the
  // `modal-trigger` controller. No-op when the hook isn't on the page.
  pageDelete() {
    const el = document.querySelector('[data-page-action="delete"]')
    if (el && typeof el.click === "function") el.click()
  }

  // `page_add_bundle` — locate the /games bundles-shelf `[+]` create
  // button by the `[data-page-action="add-bundle"]` hook and click it.
  // The button is a `button_to`-generated `<button>` inside a form
  // (POST /bundles); clicking it submits the form via Turbo, which
  // lands on `bundles/create.turbo_stream.erb` — that response
  // appends the new bundle tile to the shelf and auto-opens the
  // bundle modal so the user can rename inline. Same dispatch
  // pattern as `pageSync` / `pageDelete`. No-op when the hook isn't
  // on the page (called from a non-/games surface — though the YAML
  // only attaches `Gb` to `games_index`).
  pageAddBundle() {
    const el = document.querySelector('[data-page-action="add-bundle"]')
    if (el && typeof el.click === "function") el.click()
  }

  // `open_modal` with `modal_id: search_placeholder` — opens the
  // layout `omnisearch-modal-everywhere` <dialog> (the Phase 37
  // "Everywhere" omnisearch modal). The YAML token name
  // `search_placeholder` is retained for back-compat with existing
  // `page_actions:` entries (games_show, bundles_show, default); it
  // simply maps to whatever the canonical layout-mounted `/` modal
  // is — currently the everywhere modal. The prior legacy
  // `global-search-modal` ("search videos…" placeholder) was removed
  // from the layout on 2026-05-19 alongside this rewire.
  //
  // Resolves the dialog's Stimulus controller (`omnisearch-modal`)
  // via `window.Stimulus` and calls `open()`; falls back to a direct
  // `showModal()` if the controller isn't wired. Cross-controller
  // LOOKUP is OK here because the dialog element is the controller's
  // host — no body-mounted timing concerns.
  openGlobalSearch() {
    const dialog = document.getElementById("omnisearch-modal-everywhere")
    if (!dialog) return
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(dialog, "omnisearch-modal")
      if (ctrl && typeof ctrl.open === "function") {
        ctrl.open()
        return
      }
    }
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
    }
  }

  // `toggle_filter_chip` — delegate to the existing /games
  // filter-chip click handler so cascade rules + URL canonicalisation
  // + Turbo Frame reload all run through the one code path
  // (`games_filter_controller#toggle`). The leader-menu side stays
  // tiny: look up the chip by `[data-filter-token="<token>"]` and
  // click it. The popup has already been closed by `fireAction`
  // (`closePopup: true`), so this just kicks off the chip toggle.
  // No-op when the chip isn't on the page (token mismatch, chip
  // pruned from universe, called from a non-/games surface — though
  // the YAML only attaches `f filter` to `games_index`).
  toggleFilterChip(token) {
    const chip = document.querySelector(`[data-filter-token="${token}"]`)
    if (chip) chip.click()
  }

  // `trigger_inline_edit` — locate the element inside the currently
  // open keyed modal whose `data-modal-action-target` matches the
  // YAML `target:` value, resolve its `inline-title-edit` Stimulus
  // controller, and call `.edit()` — the same flow the `[change]`
  // link triggers. The popup was closed BEFORE this runs (fireAction
  // calls `close({ closePopup: true })`), so the modal regains focus
  // before the inline-edit input swap. The closing leader dialog
  // fires its own `close` event but `onDialogClose` ignores it via
  // the `event.target === this.popupTarget` guard.
  //
  // No-op when:
  //   * no `<dialog open>[data-modal-actions-key]` is on the page,
  //   * the open modal has no descendant with the matching hook,
  //   * the descendant has no `inline-title-edit` controller wired,
  //   * the controller exposes no `.edit` method.
  // Each silent fallback keeps a stale schema entry from throwing.
  triggerInlineEdit(target) {
    const modalDialog = document.querySelector("dialog[open][data-modal-actions-key]")
    if (!modalDialog) return
    const host = modalDialog.querySelector(`[data-modal-action-target="${target}"]`)
    if (!host) return
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(host, "inline-title-edit")
      if (ctrl && typeof ctrl.edit === "function") {
        ctrl.edit()
        return
      }
    }
  }

  // `submit_confirm_modal` — submit the form inside the currently
  // open keyed `<dialog>` via `form.requestSubmit()` so HTML5
  // validation + the form's CSRF token + native submit semantics all
  // run as if the user clicked the primary button. Used by the
  // revoke + reindex confirm modals (both ship a `[r ...]` action
  // wired here). The popup is already closed by `fireAction`
  // (`closePopup: true`); the modal stays open and processes the
  // submit normally, navigating or broadcasting as configured.
  //
  // The lookup picks the FIRST `<form>` inside the open modal — both
  // current consumers ship a single form per dialog. A future modal
  // with multiple forms would need a more specific selector; the
  // first-form contract is fine until then.
  //
  // No-op when no keyed modal is open or the modal has no form.
  submitConfirmModal() {
    const modalDialog = document.querySelector("dialog[open][data-modal-actions-key]")
    if (!modalDialog) return
    const form = modalDialog.querySelector("form")
    if (!form) return
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }

  // `open_modal_by_id` — generic helper that locates a `<dialog>` by
  // its DOM id and calls `.showModal()` to place it in the browser
  // top layer. Used by /settings page actions where the underlying
  // modal already exists on the page (mounted by the relevant pane):
  //   sr → revoke_sessions_modal      (_security_pane.html.erb)
  //   vr → reindex_meilisearch_modal  (_stack_pane.html.erb via
  //                                    ConfirmModalComponent)
  // Once the modal opens, its `data-modal-actions-key` flips the
  // leader popup into modal-scoped mode the next time the user opens
  // it (`revoke_confirm` / `reindex_confirm` modal_actions take over).
  //
  // No-op when:
  //   * the dialog id is not on the page,
  //   * the element is not a `<dialog>` (no `.showModal` function),
  //   * the dialog is already open (`.showModal()` on an already-open
  //     dialog throws `InvalidStateError` in Firefox — guard with the
  //     `open` attribute).
  // The popup was closed by `fireAction` (`closePopup: true`) before
  // this runs, so focus returns to the new modal cleanly.
  openModalById(targetId) {
    const dlg = document.getElementById(targetId)
    if (!dlg) return
    if (typeof dlg.showModal !== "function") return
    if (dlg.open) return
    dlg.showModal()
  }

  // `open_revoke_unused_modal` — purpose-built handler for /settings
  // `sr` ("revoke unused sessions"). The label encodes the user
  // intent: every session EXCEPT the current one IS the unused set.
  // A bare `open_modal_by_id` would only surface the modal with zero
  // checkboxes ticked, leaving the user to either re-select manually
  // or submit a no-op revoke.
  //
  // Flow:
  //   1. Find every session row checkbox NOT marked as the current
  //      session (`[data-current="yes"]`) and flip `checked = true`.
  //   2. Resolve the `sessions-bulk-revoke` Stimulus controller
  //      attached to the enclosing fieldset, call `update()` so the
  //      `[revoke N]` link recomputes (live count, danger styling,
  //      etc.), then call `open()` to populate the modal title /
  //      conditional warning / form action and `showModal()` the
  //      dialog. Delegating to the controller's own `open()` keeps
  //      one code path for the populate-then-open sequence — the
  //      manual `[revoke N]` click and the leader-menu sr both run
  //      through it.
  //   3. Fallback (controller missing / not resolvable): native
  //      `dlg.showModal()` so the dialog still appears. The modal
  //      title would read the placeholder text and the form action
  //      would carry the literal `0` ids segment, but this branch is
  //      defensive only — the controller is always wired on
  //      `_security_pane.html.erb`.
  //
  // No-op when the dialog id isn't on the page (e.g. user opens the
  // leader popup before the security pane mounts, or on a page that
  // doesn't render this surface at all).
  //
  // The current-session checkbox carries `data-current="yes"` via the
  // `CheckboxComponent` `data:` hash baked at render time (see
  // `_security_pane.html.erb`); the rest carry `data-current="no"`.
  // The selector scopes by `[data-sessions-bulk-revoke-target="checkbox"]`
  // (the existing target hook on every row checkbox) so the auto-check
  // is bound to the sessions table — cross-fieldset bleed onto unrelated
  // checkboxes elsewhere on /settings is impossible.
  openRevokeUnusedModal(targetId) {
    const checkboxes = document.querySelectorAll(
      'input[type="checkbox"][data-sessions-bulk-revoke-target~="checkbox"]:not([data-current="yes"])'
    )
    checkboxes.forEach((cb) => {
      if (!cb.disabled) cb.checked = true
    })

    const dlg = document.getElementById(targetId)
    if (!dlg) return

    const fieldset = dlg.closest("[data-controller~='sessions-bulk-revoke']")
    const app = window.Stimulus
    if (fieldset && app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(fieldset, "sessions-bulk-revoke")
      if (ctrl) {
        if (typeof ctrl.update === "function") ctrl.update()
        if (typeof ctrl.open === "function") {
          ctrl.open()
          return
        }
      }
    }

    // Defensive fallback — open the dialog directly if the controller
    // isn't resolvable. The pre-checked boxes still drive the bulk
    // selection, but the modal title / form action stay at their
    // placeholder values.
    if (typeof dlg.showModal === "function" && !dlg.open) {
      dlg.showModal()
    }
  }

  // `toggle_setting` — locate the page element carrying
  // `[data-leader-toggle="<target>"]` and dispatch a synthetic click
  // on it. Used by /settings 2-key bindings (da/dd/sa/sd) where the
  // underlying surface is an auto-save checkbox in the Discord /
  // Slack pane.
  //
  // Phase C ships the keybinding mechanic alone; Phase D will attach
  // the `data-leader-toggle` attributes onto the actual checkboxes
  // once the form restructure lands. Until then the hook does not
  // exist on the page and this helper silently no-ops. Once Phase D
  // ships the hooks the same bindings will start toggling for free —
  // no leader-side change required.
  //
  // `click()` is used rather than dispatching a `change` event so the
  // browser's native checkbox toggle (visual state + the auto-save
  // controller's `change` listener attached via Stimulus) runs through
  // the same path as a user click. No-op when the hook isn't present.
  toggleSetting(targetName) {
    const el = document.querySelector(`[data-leader-toggle="${targetName}"]`)
    if (!el) return
    if (typeof el.click === "function") el.click()
  }

  // `logout` — DELETE /session (route name :session_logout in
  // config/routes.rb). The header [logout] link was removed on
  // 2026-05-16; the route survives precisely so keyboard / API callers
  // can still sign out. We build a hidden form with `_method=delete` +
  // the page's CSRF token and submit it so Rails routes the request to
  // `Sessions#destroy` exactly as `button_to` would, including the
  // server-side redirect back to /login.
  performLogout() {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || ""

    const form = document.createElement("form")
    form.method = "POST"
    form.action = "/session"
    form.style.display = "none"

    const methodInput = document.createElement("input")
    methodInput.type = "hidden"
    methodInput.name = "_method"
    methodInput.value = "delete"
    form.appendChild(methodInput)

    const csrfInput = document.createElement("input")
    csrfInput.type = "hidden"
    csrfInput.name = "authenticity_token"
    csrfInput.value = csrfToken
    form.appendChild(csrfInput)

    document.body.appendChild(form)
    form.submit()
  }

  navigateTo(path) {
    if (typeof window.Turbo !== "undefined" && window.Turbo.visit) {
      window.Turbo.visit(path)
      return
    }
    window.location.assign(path)
  }

  render(menu, name) {
    if (!this.hasPopupTarget) return
    // Tear down the previous render before painting the next; we
    // build the card with `createElement` + `textContent` so no
    // dynamic strings reach the HTML parser.
    while (this.popupTarget.firstChild) this.popupTarget.removeChild(this.popupTarget.firstChild)

    const card = document.createElement("div")
    card.className = "leader-menu-card"
    card.setAttribute("role", "menu")
    card.setAttribute("aria-label", `leader menu (${name})`)

    // Two-section render at the ROOT menu (2026-05-17): page-actions
    // (OR modal_actions when a modal is open) first, hairline, then the
    // navigation menu below. Submenus (`channels`, `games`, …) render
    // only the navigation list — the page-actions block is a root-only
    // affordance because that is where the user looks to discover "what
    // can I do on THIS page". The page_actions section is omitted
    // entirely (no empty heading, no orphan hairline) when the resolved
    // list is empty — pages on the helper-side deny-list (e.g.
    // /settings) ship no `data-keybindings-page-key` and resolve to [].
    // See `KeybindingsReferenceComponent` for the Ruby-side equivalent.
    //
    // 2026-05-18 — navigation is ALWAYS rendered, including in modal
    // context. The earlier "modal_actions only" behaviour hid the
    // navigation section the moment a modal opened, which left the
    // user unable to discover (or jump to) other pages without first
    // dismissing the modal. Per locked direction, modal_actions
    // PREPEND the page-actions block while navigation remains visible
    // and dispatchable alongside. The footer hint copy still adapts
    // via the `modalContext` boolean below so the Esc affordance is
    // surfaced when a parent modal exists.
    const modalContext = this.isModalContextActive()
    if (name === "root") {
      const pageActions = this.resolvePageActions()
      if (pageActions.length > 0) {
        const pageSection = document.createElement("section")
        pageSection.className = "leader-menu-section leader-menu-page-actions"
        pageSection.setAttribute("data-section", "local")

        const pageTitle = document.createElement("div")
        pageTitle.className = "leader-menu-title text-muted"
        // Section heading renamed 2026-05-18 — "actions" → "local". The
        // earlier label confused the per-page actions with the navigation
        // section labelled "navigation" (now "global"). The Ruby-side
        // KeybindingsReferenceComponent uses the same labels.
        pageTitle.textContent = "local"
        pageSection.appendChild(pageTitle)

        // Group-aware rendering. A divider entry carrying
        // `layout: grid_2col` opens a 2-column grid that closes at the
        // next divider OR end-of-list. The grid wraps its items in a
        // `<div class="keybindings-grid keybindings-grid--two-col">`
        // with an inline `grid-template-rows: repeat(<half>, auto)` so
        // the `grid-auto-flow: column` CSS rule (in application.css)
        // fills items COLUMN-FIRST (5 left / 3 right for the 8 filter
        // chips, 1 left / 1 right for the 2 create-row items). Non-grid
        // groups render as a `<ul class="leader-menu-list">` of rows.
        // Plain dividers between groups paint as visible hairlines.
        this.appendGroupedRows(pageSection, pageActions)

        card.appendChild(pageSection)

        // Hairline always paints between page-actions and the always-
        // rendered navigation section below.
        const hr = document.createElement("hr")
        hr.className = "hairline leader-menu-hairline"
        card.appendChild(hr)
      }
    }

    {
      const navSection = document.createElement("section")
      navSection.className = "leader-menu-section leader-menu-navigation"
      if (name === "root") navSection.setAttribute("data-section", "global")

      const title = document.createElement("div")
      title.className = "leader-menu-title text-muted"
      // Display-label override map: YAML keys stay stable (a lot of
      // dispatch logic — openMenu("root"), name === "root" guards above —
      // still keys off the internal name), but the SECTION HEADER the
      // user sees gets a friendlier label. Submenu names pass through
      // unchanged via the `|| name` fallback. Renamed 2026-05-18 —
      // "navigation" → "global" to match the Ruby-side
      // KeybindingsReferenceComponent.
      const SECTION_LABELS = { root: "global" }
      title.textContent = SECTION_LABELS[name] || name
      navSection.appendChild(title)

      // Same group-aware rendering as the local section so any future
      // root-menu YAML divider can opt into a 2-col grid. Today the root
      // menu ships no `layout: grid_2col` divider, so this falls through
      // as a single-column list — identical visual output to the prior
      // flat `<ul>` rendering for the global section.
      this.appendGroupedRows(navSection, menu.items || [])
      card.appendChild(navSection)
    }

    // A5: footer copy — `Backspace clear · Space close`.
    // - Esc dropped from the default footer: A4 means Esc no longer
    //   closes the popup (falls through to parent dialog instead) on
    //   the regular page surface, so advertising it there is wrong.
    // - Backspace's dominant role is now "pop the pending prefix one
    //   char at a time" (A1); the legacy submenu pop-back still works
    //   when the prefix is empty.
    // - Space toggles per A3, so while open Space closes.
    //
    // Phase B (2026-05-17) — modal-context override: when a keyed
    // modal is open the leader popup is dialog-stacked above it; Esc
    // dismisses the PARENT modal (and the leader popup closes on the
    // parent's `close` event via `onDialogClose`). Surface that
    // affordance by prepending `Esc close modal · ` to the hint. The
    // non-modal hint stays unchanged.
    const hint = document.createElement("div")
    hint.className = "leader-menu-hint text-muted"
    hint.textContent = modalContext
      ? "Esc close modal · Backspace clear · Space close"
      : "Backspace clear · Space close"
    card.appendChild(hint)

    this.popupTarget.appendChild(card)
  }

  // Fold a flat list of `{ key, label, action }` + divider rows into
  // groups bounded by dividers and append each group to the host
  // section. A divider carrying `layout: "grid_2col"` opens a 2-col
  // grid group that closes at the next divider OR end-of-list; any
  // other divider opens a single-column group; the first run (before
  // any divider) is always single-column.
  //
  // Visual output:
  //   * single-column group → `<ul class="leader-menu-list">` of rows
  //     (existing default, preserves prior behavior).
  //   * 2-col grid group    → `<div class="keybindings-grid
  //     keybindings-grid--two-col" style="grid-template-rows: repeat(
  //     <half>, auto)">` whose children are direct `<div
  //     class="keybindings-row">` cells. The inline `grid-template-rows`
  //     pairs with the CSS `grid-auto-flow: column` rule to fill items
  //     COLUMN-FIRST (5 left / 3 right for 8 items, 1 left / 1 right
  //     for 2). Mirrors the Ruby-side
  //     `KeybindingsReferenceComponent#render_group` exactly.
  //   * plain divider between groups → `<hr class="hairline
  //     keybindings-divider">` between groups (never at top or bottom).
  appendGroupedRows(host, rows) {
    const groups = []
    let currentLayout = "single"
    let currentItems = []
    const flush = () => {
      if (currentItems.length > 0) {
        groups.push({ layout: currentLayout, items: currentItems })
      }
      currentItems = []
    }
    rows.forEach((row) => {
      if (row && row.divider) {
        flush()
        currentLayout = row.layout === "grid_2col" ? "grid_2col" : "single"
      } else {
        currentItems.push(row)
      }
    })
    flush()

    groups.forEach((group, idx) => {
      if (idx > 0) {
        const hr = document.createElement("hr")
        hr.className = "hairline keybindings-divider"
        host.appendChild(hr)
      }
      if (group.layout === "grid_2col") {
        const grid = document.createElement("div")
        grid.className = "keybindings-grid keybindings-grid--two-col"
        const half = Math.ceil(group.items.length / 2)
        grid.setAttribute("style", `grid-template-rows: repeat(${half}, auto);`)
        group.items.forEach((item) => {
          grid.appendChild(this.buildGridCell(item))
        })
        host.appendChild(grid)
      } else {
        const list = document.createElement("ul")
        list.className = "leader-menu-list"
        group.items.forEach((item) => {
          list.appendChild(this.buildItemRow(item))
        })
        host.appendChild(list)
      }
    })
  }

  // Grid-cell variant of `buildItemRow`. Same dim/highlight pending-
  // prefix treatment so the 2-col grid items participate in the
  // accumulator visuals identically to single-column rows. Uses a
  // `<div class="keybindings-row">` (NOT `<li>`) because the parent
  // is a `<div class="keybindings-grid">`, not a `<ul>`. The shared
  // `.keybindings-row` flex rules style the row identically across
  // both contexts (key gutter + label).
  buildGridCell(item) {
    const cell = document.createElement("div")
    cell.className = "keybindings-row"

    // Compact-prefix floor (2026-05-19). Hide cells whose key does not
    // start with the floor; the floor survives the inactivity-timer
    // reset that clears `pendingPrefix`, so `qQ` stays hidden across
    // a 1500ms idle in a `g` compact view. Mirrors the same block in
    // `buildItemRow`.
    if (this.compactMode && this.compactPrefix && this.compactPrefix.length > 0) {
      const key = item && typeof item.key === "string" ? item.key : ""
      if (!key.startsWith(this.compactPrefix)) cell.hidden = true
    }

    if (this.pendingPrefix && this.pendingPrefix.length > 0) {
      if (item.key && typeof item.key === "string" && item.key.startsWith(this.pendingPrefix)) {
        cell.classList.add("leader-menu-row--match")
      } else {
        cell.classList.add("leader-menu-row--dim")
        // Compact mode hides non-matching grid cells the same way it
        // hides single-column rows (see buildItemRow).
        if (this.compactMode) cell.hidden = true
      }
    }

    const keySpan = document.createElement("span")
    keySpan.className = "leader-menu-key"
    keySpan.textContent = this.displayKey(item.key)
    cell.appendChild(keySpan)

    cell.appendChild(document.createTextNode(" "))

    const labelSpan = document.createElement("span")
    labelSpan.className = "leader-menu-label"
    labelSpan.textContent = item.label || ""
    cell.appendChild(labelSpan)

    return cell
  }

  // Build a single `<li>` row for either a page-action item or a
  // menu item. Shared by both sections so the visual treatment
  // (key gutter + label + optional submenu arrow) stays identical.
  // Render the key glyph without surrounding brackets. The
  // `.leader-menu-key` rule pins `min-width: 28px` so single- and
  // multi-char keys line up across rows; this row reads as
  // `l   list`, `+   add`, `Q   logout` in the monospace
  // face. The single text-node gap keeps the visual gutter even when
  // the column is empty (defensive — schema items always have a key
  // today).
  buildItemRow(item) {
    // Divider entry (`{ divider: true }` in the YAML schema) — paint a
    // hairline `<hr>` inside an `<li>` so the parent `<ul>` stays valid
    // markup. Divider rows are non-interactive (no key gutter, no
    // label, no click handler) and are ignored by `findItem` during
    // key dispatch. Used today by /games `f filter` to fence the
    // lifecycle/ownership/engagement chips off from the platform
    // chips, but any future schema submenu can opt in the same way.
    if (item && item.divider) {
      const row = document.createElement("li")
      row.className = "leader-menu-row leader-menu-divider-row"
      row.setAttribute("role", "separator")
      row.setAttribute("aria-hidden", "true")
      // Compact mode collapses dividers entirely so a hairline never
      // floats alone above an empty navigation group.
      if (this.compactMode) row.hidden = true
      const hr = document.createElement("hr")
      hr.className = "leader-menu-divider"
      row.appendChild(hr)
      return row
    }

    const row = document.createElement("li")
    row.className = "leader-menu-row"

    // Compact-prefix floor (2026-05-19). Independent of the live
    // `pendingPrefix` accumulator: when the popup opened via flat-key
    // (`g` / `q` on the neutral page chrome), the seed prefix is the
    // floor. Rows whose key does NOT start with the floor are hidden
    // for the lifetime of the popup, so the 1500ms inactivity-timer
    // reset that clears `pendingPrefix` does NOT leak unrelated rows
    // (qQ in a `g` compact view, gC/gG/gS in a `q` compact view).
    if (this.compactMode && this.compactPrefix && this.compactPrefix.length > 0) {
      const key = item && typeof item.key === "string" ? item.key : ""
      if (!key.startsWith(this.compactPrefix)) row.hidden = true
    }

    // A1: dim/highlight rows based on the pending prefix. When the
    // user has typed `s` and `sr` is on the page, `sr` rows get the
    // `leader-menu-row--match` class (highlighted) and every other
    // row gets `leader-menu-row--dim` (muted). When the prefix is
    // empty no class is applied (rows render at default opacity).
    // Compact mode (flat-key `g` / `q` open) additionally HIDES every
    // non-matching row via the `hidden` attribute so qQ disappears
    // when the prefix is `g` and the inverse for `q`. JS-driven
    // hiding is more deterministic than the CSS-only path and works
    // even if the popup's `data-compact` attribute lands after the
    // first render (the attribute is set after `openMenu` but before
    // the prefix-seeded repaint inside `onFlatKeyOpenWithPrefix`).
    if (this.pendingPrefix && this.pendingPrefix.length > 0) {
      if (item.key && typeof item.key === "string" && item.key.startsWith(this.pendingPrefix)) {
        row.classList.add("leader-menu-row--match")
      } else {
        row.classList.add("leader-menu-row--dim")
        if (this.compactMode) row.hidden = true
      }
    }

    const keySpan = document.createElement("span")
    keySpan.className = "leader-menu-key"
    keySpan.textContent = this.displayKey(item.key)
    row.appendChild(keySpan)

    row.appendChild(document.createTextNode(" "))

    const labelSpan = document.createElement("span")
    labelSpan.className = "leader-menu-label"
    labelSpan.textContent = item.label || ""
    row.appendChild(labelSpan)

    if (item.submenu) {
      const arrow = document.createElement("span")
      arrow.className = "text-muted"
      arrow.textContent = " →"
      row.appendChild(arrow)
    }
    return row
  }

  // Resolve the page-actions list for the current page OR for the
  // currently open modal. Reads the YAML key from
  // `<body data-keybindings-page-key>` (rendered by the layout via
  // `KeybindingsHelper#keybindings_page_key`) and looks it up in
  // `schema.page_actions`.
  //
  // A2 (modal-as-page): when a `<dialog open>` carrying
  // `data-modal-actions-key="<key>"` is present, the resolver returns
  // `schema.modal_actions[<key>].items` instead — and ignores the
  // page's page_actions + nav + logout entirely. This makes the
  // leader popup MODAL-SCOPED whenever a modal is open: only the
  // modal's actions are listed. The fallback rule (no open keyed
  // dialog) preserves today's behavior — page_actions resolved by
  // the page key, with a `default:` fallback in YAML.
  //
  // Phase B adds the `data-modal-actions-key` attributes to the
  // bundle / Discord-help / Slack-help / revoke-confirm /
  // reindex-confirm dialogs and populates `modal_actions:` entries.
  // Until then `schema.modal_actions` is an empty stub and the
  // detection rule below resolves to [] when a bare modal is open
  // (which is fine — the page_actions path also returns []).
  //
  // Returns [] when:
  //   * the body attribute is missing (deny-listed page like
  //     /settings, or chrome-stripped layout) AND no modal is open
  //   * the YAML has no entry for the resolved key
  // The Ruby-side deny-list (NO_PAGE_ACTIONS_PAGES in
  // `KeybindingsReferenceComponent`) is enforced upstream by
  // omitting the data attribute entirely, so this method does not
  // need to re-check it client-side.
  resolvePageActions() {
    if (!this.schema) return []
    // Modal context wins over page context. The leader popup itself
    // is a <dialog open> but it is NOT counted here — it carries no
    // `data-modal-actions-key`, so the selector skips it cleanly.
    const modalDialog = document.querySelector("dialog[open][data-modal-actions-key]")
    if (modalDialog) {
      const modalKey = modalDialog.dataset.modalActionsKey
      const modalEntry = this.schema.modal_actions && this.schema.modal_actions[modalKey]
      const modalItems = modalEntry && Array.isArray(modalEntry.items) ? modalEntry.items : []
      return modalItems
    }
    if (!this.schema.page_actions) return []
    const pageKey = document.body?.dataset?.keybindingsPageKey
    if (!pageKey) return []
    const list = this.schema.page_actions[pageKey] || this.schema.page_actions["default"] || []
    return Array.isArray(list) ? list : []
  }

  // Detect whether a keyed modal is currently open above the leader
  // popup. As of 2026-05-18 the navigation section is ALWAYS rendered
  // regardless of modal context, so this helper no longer gates the
  // nav block — it only feeds the footer-hint copy in `render()`
  // (prepending `Esc close modal · ` when a parent modal exists so
  // the user knows Esc dismisses the parent dialog, not the leader
  // popup itself).
  isModalContextActive() {
    return !!document.querySelector("dialog[open][data-modal-actions-key]")
  }

  displayKey(key) {
    if (key === " ") return "␣"
    return key
  }

  // Pass-through gate: while focus sits on an interactive form control,
  // the leader menu MUST NOT swallow the keypress — SPACE has to land
  // in the input as a literal space, toggle the focused checkbox /
  // radio, or activate the focused button (native browser default).
  // The skip set covers every form-entry surface the user can focus:
  //
  //   * `input`         — covers all `<input>` types (text, email,
  //                       number, password, checkbox, radio, …). The
  //                       native SPACE behaviour for checkbox / radio
  //                       toggles selection; for text inputs it lands
  //                       a literal space; either way the leader popup
  //                       has no business firing.
  //   * `textarea`      — text entry.
  //   * `select`        — native dropdowns swallow SPACE to open.
  //   * `button`        — focused buttons activate on SPACE (browser
  //                       default). The leader popup MUST defer so
  //                       Tab-then-SPACE submits forms cleanly. This
  //                       matches user direction (2026-05-11): "if
  //                       focus is on an input field or textarea or
  //                       button, or checkbox, it should not trigger
  //                       as that's form functionality".
  //   * `[contenteditable]` — same logic as textarea, for rich-text
  //                           surfaces or future editor panes.
  //
  // `<a>` / link focus is intentionally OUT of this set — Tab landing
  // on a navbar link should still let the user press SPACE to open
  // the leader popup (links don't activate on SPACE in browsers
  // anyway, only Enter).
  isEditableTarget(target) {
    if (!target || !target.matches) return false
    return target.matches(
      "input, textarea, select, button, [contenteditable], [contenteditable='true']"
    )
  }

  // ---- cross-navigation state -----------------------------------

  // Stash the current menu stack so a Turbo navigation that lands on
  // a new page can rebuild the popup state. The popup div is marked
  // `data-turbo-permanent` (so the DOM survives), but the Stimulus
  // controller instance is recreated on body swap; this keeps the
  // two in sync.
  persistStack() {
    if (typeof window.sessionStorage === "undefined") return
    try {
      if (this.menuStack && this.menuStack.length > 0) {
        window.sessionStorage.setItem(STACK_STORAGE_KEY, JSON.stringify(this.menuStack))
      } else {
        window.sessionStorage.removeItem(STACK_STORAGE_KEY)
      }
    } catch (_err) {
      // Storage may be unavailable (private mode, quota); fail silently.
    }
  }

  rehydrate() {
    if (typeof window.sessionStorage === "undefined") return
    // 2026-05-21 — fresh page loads (reload, hard reload Ctrl+Shift+R,
    // back/forward cache miss, direct URL entry) clear any persisted
    // stack before reading. `turbo:visit` clears sessionStorage on
    // Turbo Drive navigations; a browser-native reload bypasses Turbo
    // entirely, so the previous open state would resurrect on every
    // hard reload and spawn the leader popup unprompted. The
    // performance navigation entry distinguishes a fresh load
    // (`type === "reload"` or `"navigate"`) from a Turbo body swap
    // (no new navigation entry — `connect()` re-runs without a
    // navigation type change).
    try {
      const navEntries = (typeof performance !== "undefined" && typeof performance.getEntriesByType === "function")
        ? performance.getEntriesByType("navigation")
        : []
      const navType = navEntries.length > 0 ? navEntries[0].type : null
      if (navType === "reload" || navType === "navigate" || navType === "back_forward") {
        window.sessionStorage.removeItem(STACK_STORAGE_KEY)
        return
      }
    } catch (_err) {
      // performance API unavailable; fall through and keep the
      // defensive rehydrate path.
    }
    let stored
    try {
      stored = window.sessionStorage.getItem(STACK_STORAGE_KEY)
    } catch (_err) {
      return
    }
    if (!stored) return
    let stack
    try {
      stack = JSON.parse(stored)
    } catch (_err) {
      window.sessionStorage.removeItem(STACK_STORAGE_KEY)
      return
    }
    if (!Array.isArray(stack) || stack.length === 0) return
    // Validate every entry against the schema before trusting it; a
    // stale stack referencing a removed menu name would otherwise
    // render an empty popup.
    const allValid = stack.every((name) => !!this.menuByName(name))
    if (!allValid) {
      window.sessionStorage.removeItem(STACK_STORAGE_KEY)
      return
    }
    this.menuStack = stack
    const top = stack[stack.length - 1]
    const menu = this.menuByName(top)
    if (!menu) return
    this.render(menu, top)
    if (this.hasPopupTarget) this.showPopup()
  }
}
