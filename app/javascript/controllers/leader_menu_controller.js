import { Controller } from "@hotwired/stimulus"

// Module-level live read of the mandatory-2FA enrollment gate.
// Mirror of the helper in `keyboard_controller.js` /
// `theme_controller.js`; kept duplicated rather than extracted to a
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
// so single-char (`l`, `+`) and multi-char (e.g. `␣`) keys still
// line up cleanly in the monospace face.
// Submenus replace the popup contents in place (no nesting);
// Backspace pops back one level, Esc closes outright. The same
// popup is the discoverable help surface — pressing the bracketed
// `[_]` link in the footer triggers `openRoot` via Stimulus
// `data-action`.
//
// The TUI side (`extras/cli/src/ui/leader_menu.rs`) parses the same
// `config/keybindings.yml` via `serde_yaml` and renders an
// equivalent Ratatui overlay; the two stacks stay in lockstep via
// the shared file.
//
// Bindings consumed here:
//   SPACE       open the root menu (or close if already open)
//   Esc         close the popup
//   Backspace   pop back one level (close at root)
//   <key>       activate the matching item: navigate, open submenu,
//               or emit a custom event (`leader-menu:action`) that
//               other controllers can react to.
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
// undimmed. The controller still installs a one-shot outside-click
// listener — clicks landing on the dialog backdrop (anywhere outside
// the inner `.leader-menu-card`) dismiss the popup.
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
// the page, or a form submission. Combined with the outside-click
// handler, this guarantees the popup never lingers after the user
// has begun navigating somewhere else. The `turbo:visit` listener
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
//   open / today / quit / quit_and_logout / etc. → dispatched as a
//     "leader-menu:action" CustomEvent on `document`; listeners
//     wired by other controllers (the notifications modal, the
//     keyboard controller's logout flow, etc.) react. Unknown
//     action types fall through and emit the same event so future
//     handlers can plug in without touching this file.
//
// Schema shape (2026-05-10 revert): root-menu rows that point to a
// submenu drop the `action` field. Pressing C/V/P/G/c/N at the root
// drills into the submenu ONLY; the user must press `l` (list) inside
// the submenu to actually navigate to /<resource>. The previous
// combined action+submenu pattern (single keystroke both navigated
// AND drilled) proved surprising and is gone — `S` (settings) and
// `h` (home) keep direct navigation because they have no submenu.
//
// The controller still defensively handles a hypothetical
// `action + submenu` item (preferring `submenu` and ignoring the
// action) so a future schema entry can't accidentally fire both.
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
    // The schema is embedded in the layout chrome; pages without it
    // simply get no leader popup (no JS errors). When the schema is
    // missing the controller registers no listeners at all — there's
    // no menu to open.
    const node = document.getElementById("pito-keybindings")
    if (!node) {
      this.schema = null
      return
    }
    try {
      this.schema = JSON.parse(node.textContent || "{}")
    } catch (_err) {
      this.schema = null
      return
    }
    this.menuStack = []
    // Inline submenus declared inside a page-action `action: { type:
    // submenu, items: [...] }` entry. Pushed onto `menuStack` by a
    // synthetic name (e.g. `inline:filter:f`) and resolved by
    // `menuByName` before falling through to `schema.menus`. Used by
    // the `f filter` submenu on /games (toggle filter chips without
    // leaving the popup); the schema gets a sub-menu without minting
    // a new top-level entry under `menus:`.
    this.inlineMenus = {}
    this.boundKeydown = this.onKeydown.bind(this)
    this.boundOutside = this.onOutsideClick.bind(this)
    this.boundTurboVisit = this.onTurboVisit.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    // Close the popup the moment any Turbo navigation begins. Pairs
    // with the outside-click listener: clicks on links outside the
    // popup already dismiss it, and `turbo:visit` also catches
    // programmatic navigations (Turbo.visit from leader-menu's own
    // action handler, form submits, prefetch-triggered visits).
    document.addEventListener("turbo:visit", this.boundTurboVisit)
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
    if (this.boundOutside) document.removeEventListener("click", this.boundOutside, true)
    if (this.boundTurboVisit) document.removeEventListener("turbo:visit", this.boundTurboVisit)
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
    this.persistStack()
    if (this.hasPopupTarget) {
      if (this.popupTarget.open) this.popupTarget.close()
      while (this.popupTarget.firstChild) this.popupTarget.removeChild(this.popupTarget.firstChild)
    }
    document.removeEventListener("click", this.boundOutside, true)
  }

  isOpen() {
    // Native `<dialog>` exposes `open` as a live attribute that
    // flips with `.showModal()` / `.close()` — read it directly
    // instead of the prior `hidden` flag.
    return this.hasPopupTarget && this.popupTarget.open === true
  }

  // ---- key handling ----------------------------------------------

  onKeydown(event) {
    if (!this.schema) return
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
      if (event.key === "Escape") {
        event.preventDefault()
        this.close()
        return
      }
      if (event.key === "Backspace") {
        event.preventDefault()
        this.popMenu()
        return
      }
      if (event.key === " ") {
        // LazyVim behavior — leader again closes.
        event.preventDefault()
        this.close()
        return
      }
      // Match the keypress against the current menu's items.
      const item = this.findItem(event.key)
      if (item) {
        event.preventDefault()
        this.activate(item)
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

  onOutsideClick(event) {
    if (!this.isOpen()) return
    // The popup is a `<dialog>` opened via `.showModal()` — the
    // dialog element itself covers the full viewport (it IS the
    // backdrop surface), so the prior `popupTarget.contains(event.target)`
    // guard would treat every click as "inside" and never dismiss.
    // Test against the inner `.leader-menu-card` instead: clicks
    // inside the visible card stay; clicks anywhere else (backdrop)
    // close the popup. The card is the only direct child of the
    // dialog after `render()`.
    const card = this.hasPopupTarget ? this.popupTarget.querySelector(".leader-menu-card") : null
    if (card && card.contains(event.target)) return
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

  // ---- menu rendering --------------------------------------------

  openMenu(name) {
    const menu = this.menuByName(name)
    if (!menu) return
    this.menuStack.push(name)
    this.persistStack()
    this.render(menu, name)
    if (this.hasPopupTarget) this.showPopup()
    // Bind outside-click on the next tick so the click that opened
    // the popup doesn't immediately close it.
    setTimeout(() => document.addEventListener("click", this.boundOutside, true), 0)
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

  // Resolve a keypress against the active menu. At the ROOT level we
  // ALSO search the resolved page-actions list — those rows are
  // rendered into the same popup card (in the top section, above the
  // nav hairline) by `render()`, so the user expects pressing their
  // key to fire the matching action. Without this, page-action keys
  // (`d` for theme_toggle on /games, `s` for page_sync on /games/:id,
  // `-` for page_delete, `/` for global search) render in the popup
  // but no-op on press — the bug fixed 2026-05-17 after three failed
  // attempts trying to route through `keyboard_controller`.
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

    // Submenu takes precedence over action (2026-05-10 revert). A
    // root-menu row pointing to a submenu drills only; the user
    // presses `l` inside the submenu to navigate. Schema entries
    // shouldn't carry both fields any more, but the precedence rule
    // is defensive — a stray `action` next to a `submenu` is silently
    // ignored.
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
  // Dispatch table (locked 2026-05-17 — leader-prefixed action keys):
  //   navigate     → Turbo.visit(action.path) / window.location.assign
  //   theme_toggle → flip <html data-theme> + persist localStorage
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
  // History: the four action-key handlers (theme_toggle / page_sync /
  // page_delete / openGlobalSearch) previously lived on
  // `keyboard_controller` and were reached via
  // `window.Stimulus.getControllerForElementAndIdentifier(<body>,
  // "keyboard")`. That cross-controller dispatch was fragile — when
  // the lookup returned null (Stimulus not yet wired, lookup timing,
  // future layout change), the guarded `if (... && kb)` branches
  // silently fell through and the action no-op'd with no console
  // error. The handlers now live inline on this controller so the
  // dispatch is a direct method call with no lookup. The methods on
  // `keyboard_controller` remain (unused) as a deprecated holdover —
  // a follow-up sweep can delete them once we're sure no other caller
  // resurfaces.
  fireAction(item, action, { closePopup }) {
    if (closePopup) this.close()

    if (action.type === "navigate" && action.path) {
      this.navigateTo(action.path)
      return
    }
    if (action.type === "theme_toggle") {
      this.themeToggle()
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
    if (action.type === "open_modal" && action.modal_id === "search_placeholder") {
      this.openGlobalSearch()
      return
    }
    if (action.type === "toggle_filter_chip" && action.token) {
      this.toggleFilterChip(action.token)
      return
    }

    document.dispatchEvent(
      new CustomEvent("leader-menu:action", {
        detail: { item: item, action: action }
      })
    )
  }

  // ---- action-key handlers (inlined from keyboard_controller) ----

  // `theme_toggle` — flips dark/light using the same semantics as
  // `theme_controller.js` (the click handler on the `[theme]` button):
  // resolve the EFFECTIVE current theme (stored value, or system
  // preference when storage is empty), flip it, write the explicit
  // next value to localStorage, and update the `data-theme` attribute
  // on `<html>`. Writing an explicit value (never removeItem) matches
  // the click handler exactly so the two surfaces stay in sync.
  themeToggle() {
    const stored = localStorage.getItem("pito-theme")
    const current = (stored === "light" || stored === "dark")
      ? stored
      : (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem("pito-theme", next)
    document.documentElement.setAttribute("data-theme", next)
    if (window.recolorCharts) setTimeout(window.recolorCharts, 50)
  }

  // `page_sync` — POSTs to `<body data-page-sync-url>` (e.g.
  // `/games/:id/resync`). On success the page's existing ActionCable
  // subscription handles the live update; we don't wait on the
  // response body. No-op when the body attribute isn't set.
  pageSync() {
    const url = document.body?.dataset?.pageSyncUrl
    if (!url) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token || "",
        Accept: "text/vnd.turbo-stream.html",
      },
    }).catch((err) => console.error("page_sync failed:", err))
  }

  // `page_delete` — opens the per-page confirm `<dialog>` by id (the
  // per-game / per-bundle delete modal). No-op when no
  // `data-page-delete-modal-id` is set or the dialog is absent.
  pageDelete() {
    const modalId = document.body?.dataset?.pageDeleteModalId
    if (!modalId) return
    const dialog = document.getElementById(modalId)
    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal()
    }
  }

  // `open_modal` with `modal_id: search_placeholder` — opens the
  // layout `global-search-modal` <dialog>. Resolves the dialog's
  // Stimulus controller (`global-search-modal`) via `window.Stimulus`
  // and calls `open()`; falls back to a direct `showModal()` if the
  // controller isn't wired. Cross-controller LOOKUP is OK here
  // because the dialog element is the controller's host — no body-
  // mounted timing concerns.
  openGlobalSearch() {
    const dialog = document.getElementById("global-search-modal")
    if (!dialog) return
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(dialog, "global-search-modal")
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
    // first, hairline, then the navigation menu below. Submenus
    // (`channels`, `games`, …) render only the navigation list — the
    // page-actions block is a root-only affordance because that is
    // where the user looks to discover "what can I do on THIS page".
    // The page_actions section is omitted entirely (no empty heading,
    // no orphan hairline) when the resolved list is empty — pages on
    // the helper-side deny-list (e.g. /settings) ship no
    // `data-keybindings-page-key` and resolve to []. See
    // `KeybindingsReferenceComponent` for the Ruby-side equivalent.
    if (name === "root") {
      const pageActions = this.resolvePageActions()
      if (pageActions.length > 0) {
        const pageSection = document.createElement("section")
        pageSection.className = "leader-menu-section leader-menu-page-actions"

        const pageTitle = document.createElement("div")
        pageTitle.className = "leader-menu-title text-muted"
        pageTitle.textContent = "actions"
        pageSection.appendChild(pageTitle)

        const pageList = document.createElement("ul")
        pageList.className = "leader-menu-list"
        pageActions.forEach((item) => {
          pageList.appendChild(this.buildItemRow(item))
        })
        pageSection.appendChild(pageList)

        card.appendChild(pageSection)

        const hr = document.createElement("hr")
        hr.className = "hairline leader-menu-hairline"
        card.appendChild(hr)
      }
    }

    const navSection = document.createElement("section")
    navSection.className = "leader-menu-section leader-menu-navigation"

    const title = document.createElement("div")
    title.className = "leader-menu-title text-muted"
    // Display-label override map: YAML keys stay stable (a lot of
    // dispatch logic — openMenu("root"), name === "root" guards above —
    // still keys off the internal name), but the SECTION HEADER the
    // user sees gets a friendlier label. Submenu names pass through
    // unchanged via the `|| name` fallback.
    const SECTION_LABELS = { root: "navigation" }
    title.textContent = SECTION_LABELS[name] || name
    navSection.appendChild(title)

    const list = document.createElement("ul")
    list.className = "leader-menu-list"
    ;(menu.items || []).forEach((item) => {
      list.appendChild(this.buildItemRow(item))
    })
    navSection.appendChild(list)
    card.appendChild(navSection)

    const hint = document.createElement("div")
    hint.className = "leader-menu-hint text-muted"
    hint.textContent = "Esc close · Backspace up · Space close"
    card.appendChild(hint)

    this.popupTarget.appendChild(card)
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
      const hr = document.createElement("hr")
      hr.className = "leader-menu-divider"
      row.appendChild(hr)
      return row
    }

    const row = document.createElement("li")
    row.className = "leader-menu-row"

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

  // Resolve the page-actions list for the current page. Reads the
  // YAML key from `<body data-keybindings-page-key>` (rendered by
  // the layout via `KeybindingsHelper#keybindings_page_key`) and
  // looks it up in `schema.page_actions`. Returns [] when:
  //   * the body attribute is missing (deny-listed page like
  //     /settings, or chrome-stripped layout)
  //   * the YAML has no entry for that page key AND no `default:`
  //     fallback exists
  // The Ruby-side deny-list (NO_PAGE_ACTIONS_PAGES in
  // `KeybindingsReferenceComponent`) is enforced upstream by
  // omitting the data attribute entirely, so this method does not
  // need to re-check it client-side.
  resolvePageActions() {
    if (!this.schema || !this.schema.page_actions) return []
    const pageKey = document.body?.dataset?.keybindingsPageKey
    if (!pageKey) return []
    const list = this.schema.page_actions[pageKey] || this.schema.page_actions["default"] || []
    return Array.isArray(list) ? list : []
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
    setTimeout(() => document.addEventListener("click", this.boundOutside, true), 0)
  }
}
