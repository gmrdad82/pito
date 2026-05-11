import { Controller } from "@hotwired/stimulus"

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
// The popup is intentionally NOT a `<dialog>` — it's a positioned
// card so the rest of the page stays interactive while it's open.
// The controller adds a one-shot outside-click listener while the
// popup is open so clicks outside it dismiss it.
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
    // simply get no leader popup (no JS errors). Same for the popup
    // target — if a page strips the chrome (auth pages set
    // `content_for(:hide_chrome)`), the controller stays silent.
    if (!this.hasPopupTarget) {
      this.schema = null
      return
    }
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
  close(event) {
    if (event) event.preventDefault()
    this.menuStack = []
    this.persistStack()
    if (this.hasPopupTarget) {
      this.popupTarget.hidden = true
      while (this.popupTarget.firstChild) this.popupTarget.removeChild(this.popupTarget.firstChild)
    }
    document.removeEventListener("click", this.boundOutside, true)
  }

  isOpen() {
    return this.hasPopupTarget && !this.popupTarget.hidden
  }

  // ---- key handling ----------------------------------------------

  onKeydown(event) {
    if (!this.schema) return
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
    if (this.hasPopupTarget && this.popupTarget.contains(event.target)) return
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
    if (this.hasPopupTarget) this.popupTarget.hidden = false
    // Bind outside-click on the next tick so the click that opened
    // the popup doesn't immediately close it.
    setTimeout(() => document.addEventListener("click", this.boundOutside, true), 0)
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
    if (!this.schema || !this.schema.menus) return null
    return this.schema.menus[name] || null
  }

  findItem(key) {
    const name = this.menuStack[this.menuStack.length - 1]
    const menu = this.menuByName(name)
    if (!menu) return null
    return (menu.items || []).find((item) => item.key === key) || null
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

    if (hasAction) {
      this.fireAction(item, action, { closePopup: true })
    }
  }

  // Run the action side-effect (navigate or emit CustomEvent) and
  // optionally close the popup. Navigation prefers `Turbo.visit` when
  // Turbo is available so the popup (mounted on `<body>`) survives
  // the page swap; it falls back to `window.location.assign` on
  // surfaces where Turbo isn't loaded (auth pages set
  // `:hide_chrome` but those pages have no popup target anyway).
  fireAction(item, action, { closePopup }) {
    if (action.type === "navigate" && action.path) {
      if (closePopup) this.close()
      this.navigateTo(action.path)
      return
    }
    if (closePopup) this.close()
    document.dispatchEvent(
      new CustomEvent("leader-menu:action", {
        detail: { item: item, action: action }
      })
    )
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

    const title = document.createElement("div")
    title.className = "leader-menu-title text-muted"
    title.textContent = name
    card.appendChild(title)

    const list = document.createElement("ul")
    list.className = "leader-menu-list"
    ;(menu.items || []).forEach((item) => {
      const row = document.createElement("li")
      row.className = "leader-menu-row"

      // Render the key glyph without surrounding brackets. The
      // `.leader-menu-key` rule pins `min-width: 28px` so single- and
      // multi-char keys line up across rows; this row reads as
      // `l   list`, `+   add`, `Q   quit + logout` in the monospace
      // face. The single text-node gap below keeps the visual gutter
      // even when the column is empty (defensive — schema items
      // always have a key today).
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

      list.appendChild(row)
    })
    card.appendChild(list)

    const hint = document.createElement("div")
    hint.className = "leader-menu-hint text-muted"
    hint.textContent = "Esc close · Backspace up · Space close"
    card.appendChild(hint)

    this.popupTarget.appendChild(card)
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
    if (this.hasPopupTarget) this.popupTarget.hidden = false
    setTimeout(() => document.addEventListener("click", this.boundOutside, true), 0)
  }
}
