import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-command-palette"
//
// FB-170 (2026-05-21) — V6 `:command` palette controller.
// FB-D4  (2026-05-22) — i18n empty value + mode dispatch + hint filter.
// Phase 1C (2026-05-24) — section-specific palette: at OPEN time the
// controller scans the DOM for the focused panel + sub-panel and
// concatenates their `data-panel-commands` JSON onto the front of the
// catalog. This mirrors `Pito::CommandPalette::Collector` (Ruby) — the
// shared shape lets Ratatui derive its palette from the same screen
// spec.
//
// Listens for `:` at document level when no input has focus and no
// dialog is open; opens the palette, focuses the input, and lets the
// user filter / cycle / run a command from the catalog encoded in
// `data-tui-command-palette-commands-value`.
//
// Key bindings inside the palette:
//   Esc        — close + return focus
//   Tab        — cycle to next suggestion
//   Shift-Tab  — cycle to previous suggestion
//   ArrowDown  — cycle next (mirror of Tab)
//   ArrowUp    — cycle previous (mirror of Shift-Tab)
//   Enter      — execute selected command
//   Backspace  — native (handled by the input element)
//
// Filtering: case-insensitive substring match against `name` OR `hint`.
// Empty query shows the full catalog. Selection is clamped to the
// filtered list bounds.
//
// Mode integration: dispatches `tui:mode-changed` with `{mode:"command"}`
// on open and `{mode:"normal"}` on close so the BST mode lozenge tracks
// palette state (ADR 0017 cable-first + BST mode contract).
export default class extends Controller {
  static targets = ["input", "list"]
  static values = { commands: Array, empty: String }

  connect() {
    this.selectedIndex = 0
    this.activeCatalog = this.commandsValue.slice()
    this.filtered = this.activeCatalog.slice()
    this.boundOpen = this.handleOpenKey.bind(this)
    this.boundOpenEvent = this.open.bind(this)
    document.addEventListener("keydown", this.boundOpen, true)
    document.addEventListener("pito:leader:open_command", this.boundOpenEvent)
    document.addEventListener("pito:action:open_command", this.boundOpenEvent)
  }

  // Phase 1C (2026-05-24) — scan the DOM for the focused panel +
  // sub-panel, parse their `data-panel-commands` JSON, and concatenate
  // sub-panel → panel → screen-scoped commands. Mirrors the Ruby
  // `Pito::CommandPalette::Collector#call` ordering so web + future
  // Ratatui clients stay in lockstep.
  collectScopedCommands() {
    const screen = this.commandsValue.slice()
    const focusedPanel = document.querySelector('[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]')
    const focusedSubPanel = document.querySelector('[data-tui-cursor-target="sub-panel"][data-tui-cursor-sub-panel-focused="yes"]')
    const subPanelCommands = this.parseCommandsAttr(focusedSubPanel)
    const panelCommands = this.parseCommandsAttr(focusedPanel)
    const annotate = (cmd, scope) => Object.assign({ scope }, cmd, cmd.scope ? { scope: cmd.scope } : {})
    return [
      ...subPanelCommands.map((c) => annotate(c, "sub_panel")),
      ...panelCommands.map((c) => annotate(c, "panel")),
      ...screen.map((c) => annotate(c, "screen"))
    ]
  }

  parseCommandsAttr(el) {
    if (!el) return []
    const raw = el.getAttribute("data-panel-commands")
    if (!raw) return []
    try {
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      return []
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundOpen, true)
    document.removeEventListener("pito:leader:open_command", this.boundOpenEvent)
    document.removeEventListener("pito:action:open_command", this.boundOpenEvent)
  }

  // Document-level `:` listener — opens the palette when no input is
  // focused, no dialog is open, and no modifier is held.
  handleOpenKey(event) {
    if (this.isOpen()) return
    if (event.key !== ":") return
    if (event.ctrlKey || event.metaKey || event.altKey) return
    if (document.querySelector("dialog[open]")) return
    const t = event.target
    if (t && t.matches && t.matches("input, textarea, select, [contenteditable='true']")) {
      return
    }
    event.preventDefault()
    event.stopPropagation()
    this.open()
  }

  isOpen() {
    return !this.element.hasAttribute("hidden")
  }

  open() {
    this.element.removeAttribute("hidden")
    this.inputTarget.value = ""
    // Phase 1C (2026-05-24) — rebuild the active catalog every open so
    // it reflects whichever panel / sub-panel the cursor is currently
    // focused on. The base `commandsValue` catalog (screen + global)
    // remains the trailing scope.
    this.activeCatalog = this.collectScopedCommands()
    this.filtered = this.activeCatalog.slice()
    this.selectedIndex = 0
    this.render()
    // Notify BST mode lozenge: palette open → command mode.
    this.dispatchMode("command")
    // Defer focus to next tick so the `:` keydown isn't captured by
    // the input itself.
    setTimeout(() => {
      this.inputTarget.focus()
    }, 0)
  }

  close() {
    this.element.setAttribute("hidden", "")
    this.inputTarget.value = ""
    // Notify BST mode lozenge: palette closed → back to normal mode.
    this.dispatchMode("normal")
  }

  // Broadcast tui:mode-changed so BST mode lozenge + any other listener
  // reflects the current mode without direct coupling to this controller.
  dispatchMode(mode) {
    document.dispatchEvent(
      new CustomEvent("tui:mode-changed", { detail: { mode }, bubbles: false })
    )
  }

  // input -> filter
  // D4 contract: substring match against `name` OR `hint` (case-insensitive).
  // Phase 1C — filter against the panel-scoped `activeCatalog` (built
  // in `open()`), not the static `commandsValue` (which only carries
  // the screen + global scope).
  filter() {
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    const all = this.activeCatalog || this.commandsValue
    if (q === "") {
      this.filtered = all.slice()
    } else {
      this.filtered = all.filter((c) =>
        (c.name || "").toLowerCase().includes(q) ||
        (c.hint || "").toLowerCase().includes(q)
      )
    }
    this.selectedIndex = 0
    this.render()
  }

  // keydown on the input -> cycle / run / close
  keydown(event) {
    const k = event.key
    if (k === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.close()
      return
    }
    if (k === "Enter") {
      event.preventDefault()
      event.stopPropagation()
      this.run()
      return
    }
    if (k === "Tab" && !event.shiftKey) {
      event.preventDefault()
      event.stopPropagation()
      this.cycleNext()
      return
    }
    if (k === "Tab" && event.shiftKey) {
      event.preventDefault()
      event.stopPropagation()
      this.cyclePrev()
      return
    }
    if (k === "ArrowDown") {
      event.preventDefault()
      event.stopPropagation()
      this.cycleNext()
      return
    }
    if (k === "ArrowUp") {
      event.preventDefault()
      event.stopPropagation()
      this.cyclePrev()
      return
    }
  }

  cycleNext() {
    if (this.filtered.length === 0) return
    this.selectedIndex = (this.selectedIndex + 1) % this.filtered.length
    this.render()
  }

  cyclePrev() {
    if (this.filtered.length === 0) return
    this.selectedIndex =
      (this.selectedIndex - 1 + this.filtered.length) % this.filtered.length
    this.render()
  }

  run() {
    const cmd = this.filtered[this.selectedIndex]
    if (!cmd) return
    this.close()
    // ADR 0018 — Action bus. Commands carrying an `action_name` are
    // dispatched through `window.Pito.dispatchAction` so confirmation +
    // POST + cable wiring stays in one canonical surface. Legacy
    // commands without `action_name` keep the original action /
    // navigate branching below.
    //
    // Phase 1C (2026-05-24) — section-specific commands also carry an
    // `args:` payload (table id + column, sync indicator target, etc.).
    // Pre-resolved client-side actions (sort_table, sync_toggle,
    // click_focusable, focus_focusable) are handled here directly so
    // they short-circuit the registry path-lookup (no Rails route, no
    // POST). Anything else with an `action_name` still flows through
    // `Pito.dispatchAction` for the canonical confirmation / submit
    // pipeline.
    if (cmd.action_name) {
      const args = cmd.args || {}
      if (cmd.action_name === "sort_table") {
        this.runSortTable(args)
        return
      }
      if (cmd.action_name === "sync_toggle") {
        this.runSyncToggle(args)
        return
      }
      if (cmd.action_name === "click_focusable") {
        this.runClickFocusable(args)
        return
      }
      if (cmd.action_name === "focus_focusable") {
        this.runFocusFocusable(args)
        return
      }
      if (window.Pito && typeof window.Pito.dispatchAction === "function") {
        // Stub action names (revoke_*, etc.) are registered in
        // `Pito::ActionRegistry` with `path: "#"` so the dispatcher
        // won't crash. The console warning makes the not-yet-wired
        // status visible to operators using palette during Phase 1C.
        try {
          window.Pito.dispatchAction(cmd.action_name)
        } catch (err) {
          // eslint-disable-next-line no-console
          console.warn(`tui-command-palette: action "${cmd.action_name}" not yet wired — ${err.message || err}`)
        }
        return
      }
    }
    if (cmd.action === "open_help") {
      // FB-ITEM-3 (2026-05-22) — converge on the `pito:action:open_help`
      // event so the `tui-help-dialog` controller handles open from both
      // leader menu (`pito:leader:open_help`) and palette paths.
      document.dispatchEvent(new CustomEvent("pito:action:open_help", { bubbles: false }))
      return
    }
    if (cmd.action === "open_about") {
      // FB-ITEM-3 (2026-05-22) — converge on the `pito:action:open_about`
      // event so the `tui-about-dialog` controller handles open from both
      // leader menu (`pito:leader:open_about`) and palette paths.
      document.dispatchEvent(new CustomEvent("pito:action:open_about", { bubbles: false }))
      return
    }
    if (cmd.action === "click" && cmd.target) {
      const el = document.querySelector(cmd.target)
      if (el) el.click()
      return
    }
    if (cmd.action === "clear_input" && cmd.target) {
      const el = document.querySelector(cmd.target)
      if (el) {
        el.value = ""
        el.dispatchEvent(new Event("input", { bubbles: true }))
        el.dispatchEvent(new Event("change", { bubbles: true }))
      }
      return
    }
    if (cmd.path) {
      this.navigate(cmd.path, cmd.method)
    }
  }

  // Phase 1C (2026-05-24) — programmatic sort. Finds the matching
  // `[data-controller="sortable-table"][data-sortable-table-id-value=<id>]`
  // block, then clicks the Nth `<th class="sortable">` (column index)
  // or matches by inner label text (when `args.column` is a string).
  runSortTable(args) {
    const tableId = args.table
    const column = args.column
    if (tableId === undefined || column === undefined) return
    const root = document.querySelector(`[data-controller~="sortable-table"][data-sortable-table-id-value="${tableId}"]`)
    if (!root) {
      // eslint-disable-next-line no-console
      console.warn(`tui-command-palette: sortable-table with id "${tableId}" not found`)
      return
    }
    const headers = root.querySelectorAll("th.sortable, th[data-action*='sortable-table#sort']")
    let target = null
    if (typeof column === "number") {
      target = headers[column]
    } else {
      const colStr = String(column).toLowerCase()
      target = Array.from(headers).find((h) => (h.textContent || "").toLowerCase().includes(colStr))
    }
    if (target && typeof target.click === "function") target.click()
  }

  // Phase 1C (2026-05-24) — programmatic sync indicator toggle. Finds
  // `[data-sync-target=<name>]` and clicks. The element is a
  // `Tui::SyncIndicatorComponent` checkbox; click toggles the active
  // state and broadcasts through the existing controller.
  runSyncToggle(args) {
    const target = args.target
    if (!target) return
    const el = document.querySelector(`[data-sync-target="${target}"]`)
    if (el && typeof el.click === "function") {
      el.click()
    } else {
      // eslint-disable-next-line no-console
      console.warn(`tui-command-palette: sync target "${target}" not found — TODO wire in Phase 2`)
    }
  }

  // Phase 1C (2026-05-24) — programmatic click on a named focusable.
  // The focusable lives inside the focused panel / sub-panel scope so
  // the query is rooted at the focused panel when present.
  runClickFocusable(args) {
    const key = args.focusable
    if (!key) return
    const scope = document.querySelector('[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]') || document
    const el = scope.querySelector(`[data-tui-focusable="${key}"]`)
    if (el && typeof el.click === "function") {
      el.click()
    } else {
      // eslint-disable-next-line no-console
      console.warn(`tui-command-palette: focusable "${key}" not found in focused scope — TODO wire in Phase 2`)
    }
  }

  // Phase 1C (2026-05-24) — programmatic focus on a named focusable
  // (e.g. the Discord webhook input).
  runFocusFocusable(args) {
    const key = args.focusable
    if (!key) return
    const scope = document.querySelector('[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]') || document
    const el = scope.querySelector(`[data-tui-focusable="${key}"]`)
    if (el) {
      // Many focusables wrap an inner input — prefer focusing the
      // innermost input/textarea/contenteditable; fall back to the
      // focusable root.
      const inner = el.querySelector("input, textarea, [contenteditable='true']")
      const target = inner || el
      if (typeof target.focus === "function") target.focus()
    } else {
      // eslint-disable-next-line no-console
      console.warn(`tui-command-palette: focusable "${key}" not found in focused scope — TODO wire in Phase 2`)
    }
  }

  navigate(path, method) {
    const m = (method || "get").toLowerCase()
    if (m === "get") {
      window.location.href = path
      return
    }
    // For non-GET, submit a synthetic form so the browser sends the
    // request with the correct method + CSRF token (Rails / Turbo).
    const form = document.createElement("form")
    form.method = "post"
    form.action = path
    form.style.display = "none"
    if (m !== "post") {
      const methodInput = document.createElement("input")
      methodInput.type = "hidden"
      methodInput.name = "_method"
      methodInput.value = m
      form.appendChild(methodInput)
    }
    const csrf = document.querySelector('meta[name="csrf-token"]')
    if (csrf) {
      const tokenInput = document.createElement("input")
      tokenInput.type = "hidden"
      tokenInput.name = "authenticity_token"
      tokenInput.value = csrf.getAttribute("content")
      form.appendChild(tokenInput)
    }
    document.body.appendChild(form)
    form.submit()
  }

  // Re-paint the suggestion list from `this.filtered` and the current
  // `this.selectedIndex`. Active row gets the `▶` marker + the active
  // class. Uses createElement / textContent end-to-end so user input
  // and command catalog strings can never be interpreted as HTML.
  render() {
    if (!this.hasListTarget) return
    const list = this.listTarget
    while (list.firstChild) list.removeChild(list.firstChild)

    if (this.filtered.length === 0) {
      const empty = document.createElement("div")
      empty.className = "tui-command-palette__empty"
      // Use the i18n string from the data attribute (set by the Ruby component).
      empty.textContent = this.hasEmptyValue ? this.emptyValue : "no matches"
      list.appendChild(empty)
      return
    }

    this.filtered.forEach((c, idx) => {
      const active = idx === this.selectedIndex
      const row = document.createElement("div")
      row.className = active
        ? "tui-command-palette__item tui-command-palette__item--active"
        : "tui-command-palette__item"

      const marker = document.createElement("span")
      marker.className = "tui-command-palette__marker"
      marker.textContent = active ? "▶" : " "
      row.appendChild(marker)

      const verb = document.createElement("span")
      verb.className = "tui-command-palette__verb"
      verb.textContent = ":" + (c.name || "")
      row.appendChild(verb)

      const hint = document.createElement("span")
      hint.className = "tui-command-palette__hint"
      hint.textContent = c.hint || ""
      row.appendChild(hint)

      list.appendChild(row)
    })
  }
}
