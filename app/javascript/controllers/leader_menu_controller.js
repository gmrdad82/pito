import { Controller } from "@hotwired/stimulus"

// Leader-menu popup controller. Reads the unified keybindings schema
// embedded by the layout in `<script id="pito-keybindings">`,
// listens for SPACE on the document, and paints a small bottom-right
// popup card listing the current-menu items as `[key] label` rows.
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
// Item shape (from the schema):
//   { key: "h", label: "home", action: { type: "navigate", path: "/" } }
//   { key: "C", label: "channels", submenu: "channels" }
//
// Action types recognized:
//   navigate         { path: "/..." }            → window.location.assign(path)
//   open / today / quit / quit_and_logout / etc. → dispatched as a
//     "leader-menu:action" CustomEvent on `document`; listeners
//     wired by other controllers (the notifications modal, the
//     keyboard controller's logout flow, etc.) react. Unknown
//     action types fall through and emit the same event so future
//     handlers can plug in without touching this file.
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
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    if (this.boundKeydown) document.removeEventListener("keydown", this.boundKeydown)
    if (this.boundOutside) document.removeEventListener("click", this.boundOutside, true)
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
    // Never swallow keys while typing.
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

  // ---- menu rendering --------------------------------------------

  openMenu(name) {
    const menu = this.menuByName(name)
    if (!menu) return
    this.menuStack.push(name)
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
    if (item.submenu) {
      this.openMenu(item.submenu)
      return
    }
    const action = item.action
    if (!action || !action.type) return
    if (action.type === "navigate" && action.path) {
      this.close()
      window.location.assign(action.path)
      return
    }
    // For non-navigate actions we emit a CustomEvent so other
    // controllers can plug in handlers (e.g. notifications modal,
    // logout flow, contextual add modals) without coupling this
    // controller to every action type.
    this.close()
    document.dispatchEvent(
      new CustomEvent("leader-menu:action", {
        detail: { item: item, action: action }
      })
    )
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

      const keySpan = document.createElement("span")
      keySpan.className = "leader-menu-key"
      keySpan.textContent = `[${this.displayKey(item.key)}]`
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

  isEditableTarget(target) {
    if (!target || !target.matches) return false
    return target.matches("input, textarea, select, [contenteditable], [contenteditable='true']")
  }
}
