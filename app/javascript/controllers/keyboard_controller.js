import { Controller } from "@hotwired/stimulus"

// Phase 7.5 — Step 04. Global keyboard shortcuts.
//
// Mirrors the `pito` CLI keymap (`extras/cli/src/keys.rs`) per locked
// decision Q6 (strict mirror). The CLI is the source of truth; this
// controller follows.
//
// Bindings:
//   Global
//     ?           toggle help dialog
//     t           toggle theme (handled by theme_controller — we still
//                 surface it in the help dialog). Was `n` pre-redesign.
//     /           open the global search modal (`#global-search-modal`)
//     i           open the IGDB-search modal (`#igdb-search-modal`)
//     Esc         close any open dialog / clear pending prefix
//   Navigation (`g` prefix, ~1s timeout)
//     g d         /            (dashboard)
//     g c         /channels
//     g v         /videos
//     g s         /saved_views
//     g e         /settings
//   Filter (`f` prefix, ~1s timeout)
//     f s         click the [starred]   filter chip on the current page
//     f c         click the [connected] filter chip on the current page
//   List rows (j/k highlight, b/space/s/c/D/Y) — best-effort:
//     j / k       move highlight down / up among `[data-keyboard-row]` elements
//     space       toggle the highlighted row's bulk-select checkbox
//     b           click the [bulk] toggle if present (bulk-select#toggleBulk)
//     s           click the highlighted row's `[data-keyboard-action="star"]` link
//     D           navigate to /deletions/:type/:ids (bulk selection or highlighted id)
//     Y           navigate to /syncs/:type/:ids
//   Detail pages
//     v           open `data-keyboard-external-url` in a new tab
//     s / Y / D   click the analog action link in the page chrome
//   Action confirmation page
//     y           submit the action form
//     Esc / other clicks the [cancel] link
//
// Bindings are gated when focus sits inside `<input>`, `<textarea>`,
// `<select>`, or `[contenteditable]`, mirroring the CLI's "search
// overlay swallows keys" rule.
//
// Implementation notes:
// - Prefix state machine carries `pendingPrefix` (`null`, `"g"`, `"f"`)
//   with a 1000ms timeout so abandoned prefixes don't strand the user.
// - The controller is attached to `<body>` via `data-controller="keyboard"`
//   and adds a single document-level `keydown` listener.
// - The dialog target is the help overlay; `showModal()` /  `close()`
//   open and close it.
export default class extends Controller {
  static targets = ["dialog"]

  static PREFIX_TIMEOUT_MS = 1000

  connect() {
    this.pendingPrefix = null
    this.prefixTimer = null
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    this.clearPrefix()
  }

  // Public: open the help dialog. Wired to the visible `[ ? ]` link
  // via `data-action="click->keyboard#openHelp"`.
  openHelp(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  clickOutside(event) {
    if (this.hasDialogTarget && event.target === this.dialogTarget) {
      this.dialogTarget.close()
    }
  }

  onKeydown(event) {
    // Hard guard: never intercept while typing.
    if (this.isEditableTarget(event.target)) return

    // Browser-native shortcuts always pass through. We never bind on a
    // modifier key — `Ctrl+F`, `Cmd+K`, etc. stay native.
    if (event.metaKey || event.ctrlKey || event.altKey) return

    // Esc handling: cancel pending prefix, close dialog, then page
    // semantics (action-screen cancel link).
    if (event.key === "Escape") {
      if (this.pendingPrefix) {
        this.clearPrefix()
        event.preventDefault()
        return
      }
      if (this.hasDialogTarget && this.dialogTarget.open) {
        this.dialogTarget.close()
        event.preventDefault()
        return
      }
      if (this.handleActionScreenCancel()) {
        event.preventDefault()
        return
      }
      return
    }

    // If a dialog is open, only `?` (toggle) and Esc (above) are bound.
    // Let the rest pass through so `<dialog>` semantics stay intact.
    if (this.hasDialogTarget && this.dialogTarget.open) {
      if (event.key === "?") {
        event.preventDefault()
        this.dialogTarget.close()
      }
      return
    }

    // Prefix-second-key dispatch.
    if (this.pendingPrefix === "g") {
      this.clearPrefix()
      this.handleGPrefix(event)
      return
    }
    if (this.pendingPrefix === "f") {
      this.clearPrefix()
      this.handleFPrefix(event)
      return
    }

    // Action confirmation page: `y` submits, anything else falls through
    // to the generic handlers (Esc handled above). The page is detected
    // by the presence of an opt-in `data-keyboard-confirmation` form.
    if (event.key === "y" && this.handleActionScreenConfirm()) {
      event.preventDefault()
      return
    }

    // Single-key bindings.
    switch (event.key) {
      case "?":
        event.preventDefault()
        if (this.hasDialogTarget) this.dialogTarget.showModal()
        return
      case "/":
        if (this.openGlobalSearch()) event.preventDefault()
        return
      case "i":
        if (this.openIgdbSearch()) event.preventDefault()
        return
      case "g":
        this.beginPrefix("g")
        event.preventDefault()
        return
      case "f":
        this.beginPrefix("f")
        event.preventDefault()
        return
      case "j":
        if (this.moveHighlight(1)) event.preventDefault()
        return
      case "k":
        if (this.moveHighlight(-1)) event.preventDefault()
        return
      case " ":
        if (this.toggleHighlightedCheckbox()) event.preventDefault()
        return
      case "b":
        if (this.clickPageAction("bulk-toggle")) event.preventDefault()
        return
      case "s":
        if (this.clickRowOrPageAction("star")) event.preventDefault()
        return
      case "v":
        if (this.openExternalUrl()) event.preventDefault()
        return
      case "D":
        if (this.navigateBulk("delete")) event.preventDefault()
        return
      case "Y":
        if (this.navigateBulk("sync")) event.preventDefault()
        return
    }
  }

  // ---------- prefix state ----------

  beginPrefix(prefix) {
    this.pendingPrefix = prefix
    if (this.prefixTimer) clearTimeout(this.prefixTimer)
    this.prefixTimer = setTimeout(() => this.clearPrefix(), this.constructor.PREFIX_TIMEOUT_MS)
  }

  clearPrefix() {
    this.pendingPrefix = null
    if (this.prefixTimer) {
      clearTimeout(this.prefixTimer)
      this.prefixTimer = null
    }
  }

  handleGPrefix(event) {
    const map = { d: "/", c: "/channels", v: "/videos", s: "/saved_views", e: "/settings" }
    const path = map[event.key]
    if (path) {
      event.preventDefault()
      window.location.assign(path)
    }
  }

  handleFPrefix(event) {
    const map = { s: "starred", c: "connected" }
    const param = map[event.key]
    if (!param) return
    // Click the matching filter chip on the current page if one is rendered.
    const chip = document.querySelector(
      `[data-keyboard-filter-chip="${param}"], [data-filter-chip="${param}"] a, .filter-chip[data-param="${param}"] a`
    )
    if (chip) {
      event.preventDefault()
      chip.click()
    }
  }

  // ---------- helpers ----------

  isEditableTarget(target) {
    if (!target || !target.matches) return false
    return target.matches("input, textarea, select, [contenteditable], [contenteditable='true']")
  }

  // Phase 14 §1 polish — `/` opens the global search modal
  // (`shared/_search_modal`). The inline navbar search input it
  // used to focus was retired in the same dispatch. Returning
  // `false` from here lets the keystroke fall through (e.g. into
  // an open page-local search input) instead of swallowing it.
  openGlobalSearch() {
    return this.openLayoutDialog("global-search-modal", "global-search-modal")
  }

  // Phase 14 §1 polish — `i` opens the IGDB-search modal
  // (`shared/_igdb_search_modal`). Same shape as `/` above:
  // returning `false` lets the keystroke pass through if the
  // dialog isn't on the page (older or stripped layouts).
  openIgdbSearch() {
    return this.openLayoutDialog("igdb-search-modal", "igdb-search-modal")
  }

  // Resolves the layout-level <dialog> by id, looks up its
  // controller via `window.Stimulus`, and calls `open()`. Falls
  // back to a direct `showModal()` if the controller isn't wired.
  // Returns true when a dialog was opened, false otherwise.
  openLayoutDialog(elementId, controllerIdentifier) {
    const dialog = document.getElementById(elementId)
    if (!dialog) return false
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(dialog, controllerIdentifier)
      if (ctrl && typeof ctrl.open === "function") {
        ctrl.open()
        return true
      }
    }
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
      return true
    }
    return false
  }

  // ---------- list-row highlight ----------
  //
  // A page opts in by tagging its row container with
  // `data-keyboard-rows` and each row with `data-keyboard-row`. The
  // controller adds a `keyboard-highlight` class to the active row.

  rowElements() {
    return Array.from(document.querySelectorAll("[data-keyboard-row]"))
  }

  highlightedRow() {
    return document.querySelector("[data-keyboard-row].keyboard-highlight")
  }

  moveHighlight(delta) {
    const rows = this.rowElements()
    if (rows.length === 0) return false
    const current = this.highlightedRow()
    let nextIndex
    if (!current) {
      nextIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      const currentIndex = rows.indexOf(current)
      nextIndex = currentIndex + delta
      if (nextIndex < 0) nextIndex = 0
      if (nextIndex > rows.length - 1) nextIndex = rows.length - 1
      current.classList.remove("keyboard-highlight")
    }
    rows[nextIndex].classList.add("keyboard-highlight")
    rows[nextIndex].scrollIntoView({ block: "nearest" })
    return true
  }

  toggleHighlightedCheckbox() {
    const row = this.highlightedRow()
    if (!row) return false
    const checkbox = row.querySelector('input[type="checkbox"]')
    if (!checkbox || checkbox.disabled || checkbox.hidden) return false
    // Don't toggle when bulk mode is off — the checkbox column is hidden
    // in that mode, mirroring the CLI's gated `space` semantics.
    const computed = window.getComputedStyle(checkbox)
    if (computed.display === "none" || computed.visibility === "hidden") return false
    checkbox.click()
    return true
  }

  // ---------- per-row / per-page actions ----------

  clickPageAction(action) {
    const target = document.querySelector(`[data-keyboard-page-action="${action}"]`)
    if (!target) return false
    target.click()
    return true
  }

  clickRowOrPageAction(action) {
    const row = this.highlightedRow()
    if (row) {
      const rowAction = row.querySelector(`[data-keyboard-action="${action}"]`)
      if (rowAction) {
        rowAction.click()
        return true
      }
    }
    return this.clickPageAction(action)
  }

  openExternalUrl() {
    const node =
      this.highlightedRow()?.querySelector("[data-keyboard-external-url]") ||
      document.querySelector("[data-keyboard-external-url]")
    if (!node) return false
    const url = node.getAttribute("data-keyboard-external-url")
    if (!url) return false
    window.open(url, "_blank", "noopener,noreferrer")
    return true
  }

  navigateBulk(kind) {
    // bulk selection (one or more rows checked) takes priority, falling
    // back to the highlighted row's id and finally a page-level action.
    const ids = this.bulkSelectedIds()
    const type = this.recordType()
    if (ids.length > 0 && type) {
      const path = kind === "delete" ? `/deletions/${type}/${ids.join(",")}` : `/syncs/${type}/${ids.join(",")}`
      window.location.assign(path)
      return true
    }
    const row = this.highlightedRow()
    if (row && type) {
      const id = row.getAttribute("data-keyboard-row-id")
      if (id) {
        const path = kind === "delete" ? `/deletions/${type}/${id}` : `/syncs/${type}/${id}`
        window.location.assign(path)
        return true
      }
    }
    return this.clickPageAction(kind)
  }

  bulkSelectedIds() {
    const rows = this.rowElements()
    const ids = []
    rows.forEach((r) => {
      const checkbox = r.querySelector('input[type="checkbox"]')
      if (checkbox && checkbox.checked && !checkbox.disabled) {
        const value = r.getAttribute("data-keyboard-row-id") || checkbox.value
        if (value) ids.push(value)
      }
    })
    return ids
  }

  recordType() {
    const node = document.querySelector("[data-keyboard-record-type]")
    return node ? node.getAttribute("data-keyboard-record-type") : null
  }

  // ---------- action confirmation page ----------

  handleActionScreenConfirm() {
    const form = document.querySelector("form[data-keyboard-confirmation]")
    if (!form) return false
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
    return true
  }

  handleActionScreenCancel() {
    const cancel = document.querySelector("[data-keyboard-confirmation-cancel]")
    if (!cancel) return false
    if (cancel instanceof HTMLAnchorElement) {
      window.location.assign(cancel.href)
    } else {
      cancel.click()
    }
    return true
  }
}
