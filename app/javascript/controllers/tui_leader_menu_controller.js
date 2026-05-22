import { Controller } from "@hotwired/stimulus"

/**
 * @module controllers/leader_menu
 *
 * @contract
 * Beta 4 — D5 (2026-05-22). Clean rebuild after the 1700-line
 * nested-submenu / flat-key / compact-mode prior controller was deemed
 * spaghetti. 1-level shallow. Always single-keystroke commit.
 *
 *   1. User in NORMAL mode presses SPACE on the body (NOT inside any
 *      input / textarea / select / button / [contenteditable]).
 *   2. Controller calls `showModal()` on `#tui-leader-menu`.
 *   3. User types ONE next-key (h / v / g / ? / : / q / a). Controller
 *      finds the matching `<li data-leader-key="...">` and resolves it:
 *        - `data-leader-path` present → Turbo.visit(path) (or POST/DELETE
 *          via a hidden form when `data-leader-path-method` is set).
 *        - `data-leader-action-name` present → `window.Pito.dispatchAction(name)`.
 *        - `data-leader-dispatch-method` present → CustomEvent
 *          `pito:leader:<method>` on document; layout-mounted listeners
 *          (help dialog, about dialog, command palette) hook in.
 *   4. Dialog closes. Any unknown key is ignored (dialog stays open).
 *   5. Esc closes (native <dialog> behavior, augmented by tui-dialog
 *      controller). Esc does NOT fire a leader action.
 *
 * Guards (preventing all the bugs the prior controller accumulated):
 *   - INSERT mode: ignore SPACE entirely. Mode tracked via the
 *     `tui:mode-changed` document event (tui_cursor_controller is the
 *     state machine owner).
 *   - Focused form control: SPACE passes through (don't open).
 *   - Another <dialog open> on the page: ignore SPACE (don't shadow).
 *   - Modifier keys (Ctrl/Meta/Alt): pass through.
 *   - SPACE: preventDefault on the keydown so the page doesn't scroll.
 *
 * Mount point: `<body data-controller="... tui-leader-menu">` (added
 * by the layout). The component is rendered once at the end of `<body>`
 * via `<%= render Tui::LeaderMenuComponent.new %>`.
 *
 * @testability
 * No JS unit tests in this project. The contract above is the spec.
 * The backing Ruby surfaces (`Tui::LeaderMenuComponent`,
 * `Tui::LeaderMenuEntryComponent`) carry RSpec coverage deferred to the
 * P9 sweep per the dispatch's "DEFER specs" directive.
 */
export default class extends Controller {
  connect() {
    this.mode = "normal"
    this.dialog = null
    this.boundKeydown = this.onKeydown.bind(this)
    this.boundModeChanged = this.onModeChanged.bind(this)
    this.boundTurboVisit = this.onTurboVisit.bind(this)

    document.addEventListener("keydown", this.boundKeydown)
    document.addEventListener("tui:mode-changed", this.boundModeChanged)
    document.addEventListener("turbo:visit", this.boundTurboVisit)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener("tui:mode-changed", this.boundModeChanged)
    document.removeEventListener("turbo:visit", this.boundTurboVisit)
  }

  // Public entry point — wired to the bottom-status-bar `[_]` action
  // via `data-action="click->tui-leader-menu#openRoot"`. Toggle: a
  // second click closes the dialog (parity with LazyVim leader-double-tap).
  openRoot(event) {
    if (event) event.preventDefault()
    const dialog = this.findDialog()
    if (!dialog) return
    if (dialog.open) {
      this.closeDialog()
    } else {
      this.openDialog()
    }
  }

  onModeChanged(event) {
    const next = event && event.detail && event.detail.mode
    if (typeof next === "string") this.mode = next
  }

  onTurboVisit() {
    // Any Turbo navigation closes the dialog — defensive cleanup if
    // an entry happened to open the popup without dismissing it.
    this.closeDialog()
  }

  onKeydown(event) {
    const dialog = this.findDialog()
    if (!dialog) return

    if (dialog.open) {
      this.handleOpenDialogKey(event, dialog)
      return
    }

    // Dialog closed — only SPACE matters.
    if (event.key !== " " && event.code !== "Space") return
    if (event.ctrlKey || event.metaKey || event.altKey) return
    if (this.mode !== "normal") return
    if (this.isEditableTarget(event.target)) return
    if (this.anotherDialogOpen(dialog)) return

    event.preventDefault()
    this.openDialog()
  }

  // While the leader dialog is open, intercept the FIRST printable key
  // (or the matching next-key) and resolve. Esc falls through to the
  // native <dialog> Esc handling (the tui-dialog controller installed
  // by Tui::DialogComponent owns backdrop-click guard + close event).
  handleOpenDialogKey(event, dialog) {
    if (event.key === "Escape") return // native <dialog> + tui-dialog handle close
    if (event.ctrlKey || event.metaKey || event.altKey) return
    if (event.key === "Shift") return
    if (event.key.length !== 1) return // ignore Tab, Enter, arrow keys, etc.

    const key = event.key
    const entry = dialog.querySelector(`[data-leader-key="${this.cssEscape(key)}"]`)
    if (!entry) return // unknown key — leave dialog open, no commit

    event.preventDefault()
    event.stopPropagation()
    this.activate(entry)
    this.closeDialog()
  }

  activate(entry) {
    const path = entry.getAttribute("data-leader-path")
    const pathMethod = entry.getAttribute("data-leader-path-method")
    const actionName = entry.getAttribute("data-leader-action-name")
    const dispatchMethod = entry.getAttribute("data-leader-dispatch-method")

    if (actionName && window.Pito && typeof window.Pito.dispatchAction === "function") {
      window.Pito.dispatchAction(actionName)
      return
    }

    if (dispatchMethod) {
      document.dispatchEvent(new CustomEvent(`pito:leader:${dispatchMethod}`, { bubbles: false }))
      return
    }

    if (path) {
      if (pathMethod && pathMethod.toLowerCase() !== "get") {
        this.submitForm(path, pathMethod)
      } else {
        this.navigate(path)
      }
      return
    }
    // No-op: entry without a resolvable action — silent.
  }

  navigate(path) {
    if (window.Turbo && typeof window.Turbo.visit === "function") {
      window.Turbo.visit(path)
    } else {
      window.location.assign(path)
    }
  }

  // Builds a hidden form to POST/DELETE/PATCH to `path` with the CSRF
  // token — used for the `q logout` entry that DELETEs `/session`.
  submitForm(path, method) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = path
    form.style.display = "none"

    const csrfMeta = document.querySelector('meta[name="csrf-token"]')
    if (csrfMeta) {
      const csrf = document.createElement("input")
      csrf.type = "hidden"
      csrf.name = "authenticity_token"
      csrf.value = csrfMeta.content
      form.appendChild(csrf)
    }

    const upper = method.toUpperCase()
    if (upper !== "POST") {
      const methodInput = document.createElement("input")
      methodInput.type = "hidden"
      methodInput.name = "_method"
      methodInput.value = upper.toLowerCase()
      form.appendChild(methodInput)
    }

    document.body.appendChild(form)
    form.requestSubmit()
  }

  openDialog() {
    const dialog = this.findDialog()
    if (!dialog || dialog.open) return
    dialog.showModal()
  }

  closeDialog() {
    const dialog = this.findDialog()
    if (!dialog || !dialog.open) return
    dialog.close()
  }

  findDialog() {
    if (this.dialog && document.contains(this.dialog)) return this.dialog
    this.dialog = document.getElementById("tui-leader-menu")
    return this.dialog
  }

  anotherDialogOpen(leaderDialog) {
    const dialogs = document.querySelectorAll("dialog[open]")
    for (const d of dialogs) {
      if (d !== leaderDialog) return true
    }
    return false
  }

  isEditableTarget(target) {
    if (!(target instanceof HTMLElement)) return false
    const tag = target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || tag === "BUTTON") return true
    if (target.isContentEditable) return true
    return false
  }

  cssEscape(value) {
    if (window.CSS && typeof window.CSS.escape === "function") return window.CSS.escape(value)
    return value.replace(/(["\\])/g, "\\$1")
  }
}
