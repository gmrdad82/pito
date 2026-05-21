import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-command-palette"
//
// FB-170 (2026-05-21) — V6 `:command` palette controller.
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
// Filtering: case-insensitive substring match against `name`. Empty
// query shows the full catalog. Selection is clamped to the filtered
// list bounds.
export default class extends Controller {
  static targets = ["input", "list"]
  static values = { commands: Array }

  connect() {
    this.selectedIndex = 0
    this.filtered = this.commandsValue.slice()
    this.boundOpen = this.handleOpenKey.bind(this)
    document.addEventListener("keydown", this.boundOpen, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundOpen, true)
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
    this.filtered = this.commandsValue.slice()
    this.selectedIndex = 0
    this.render()
    // Defer focus to next tick so the `:` keydown isn't captured by
    // the input itself.
    setTimeout(() => {
      this.inputTarget.focus()
    }, 0)
  }

  close() {
    this.element.setAttribute("hidden", "")
    this.inputTarget.value = ""
  }

  // input -> filter
  filter() {
    const q = (this.inputTarget.value || "").toLowerCase().trim()
    const all = this.commandsValue
    if (q === "") {
      this.filtered = all.slice()
    } else {
      this.filtered = all.filter((c) => (c.name || "").toLowerCase().includes(q))
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
    if (cmd.action_name && window.Pito && typeof window.Pito.dispatchAction === "function") {
      window.Pito.dispatchAction(cmd.action_name)
      return
    }
    if (cmd.action === "open_help") {
      const dialog = document.getElementById("tui-help-overlay")
      if (dialog && typeof dialog.showModal === "function") dialog.showModal()
      return
    }
    if (cmd.action === "open_about") {
      const dialog = document.getElementById("about-modal")
      if (dialog && typeof dialog.showModal === "function") dialog.showModal()
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
      empty.textContent = "no matches"
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
