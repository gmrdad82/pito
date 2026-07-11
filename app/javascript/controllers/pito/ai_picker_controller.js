// pito--ai-picker
//
// Drives the /config ai overlay (Pito::Ai::PickerComponent): the OpenCode-style
// model picker across every provider in ai_providers.yml. The overlay is
// mounted on demand by a turbo stream and REMOVED on close — no hidden idle
// state. All markup is server-rendered; this controller only navigates rows,
// toggles what exists, and persists through PATCH /settings/ai:
//
//   model row + enter/click → { provider, model }   (● marker moves)
//   connect row             → reveals that provider's key input;
//     its enter             → { provider, api_key } (chip flips, never echoed)
//   effort row + enter      → cycles off→low→medium→high → { effort }
//   ctrl+f on a model row   → { favorite: "provider/model" } (★ toggles)
//   ctrl+x                  → { provider-of-selected-row, clear_key: true }
//   esc / backdrop          → close (remove the overlay); esc INSIDE a key
//     input backs out to the list first. The keydown listener runs in the
//     CAPTURE phase on window so no other capture handler (pito--resume's
//     document-level Escape, the chatbox palettes) can swallow the keys while
//     the picker is open — it is modal. The title row's Esc hint is a
//     ShortcutComponent, so on touch a tap synthesizes the keystroke.

import { Controller } from "@hotwired/stimulus"

const STATUS_FLASH_MS = 2500
const EFFORT_CYCLE = ["off", "low", "medium", "high"]

export default class extends Controller {
  static values = { endpoint: String }

  static targets = [ "row", "keyInput", "keyChip", "search", "list", "status", "effortValue" ]

  connect() {
    this.abort = new AbortController()
    window.addEventListener("keydown", (e) => this.#keydown(e), { capture: true, signal: this.abort.signal })
    this.searchTarget.focus()
    this.#select(this.#visibleRows()[0] || null)
  }

  disconnect() {
    this.abort?.abort()
    clearTimeout(this.statusTimer)
  }

  close() {
    this.element.remove()
  }

  // Click path — routes by the row's declared type, same as keyboard enter.
  activate(event) {
    this.#select(event.currentTarget)
    this.#enter(event.currentTarget)
  }

  async saveKey(event) {
    const input    = event.currentTarget
    const provider = input.dataset.provider
    const key      = input.value.trim()
    if (key === "") return

    const response = await this.#request({ provider, api_key: key })
    if (!response || !response.ok) return this.#flash("could not save key")

    input.value  = ""
    input.hidden = true
    this.#setChip(provider, true)
    this.#connectRow(provider)?.setAttribute("hidden", "")
    this.#flash(`${provider} key saved`)
    this.searchTarget.focus()
  }

  filter() {
    const needle = this.searchTarget.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => {
      if (row.dataset.rowType !== "model") return

      const haystack = `${row.dataset.provider}/${row.dataset.value}`.toLowerCase()
      row.hidden = needle !== "" && !haystack.includes(needle)
    })
    this.#select(this.#visibleRows()[0] || null)
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopImmediatePropagation()
      const open = this.#openKeyInput()
      if (open) return this.#hideKeyInput(open)
      return this.close()
    }
    if (event.ctrlKey && event.key.toLowerCase() === "x") {
      event.preventDefault()
      event.stopImmediatePropagation()
      return this.#clearKey()
    }
    if (event.ctrlKey && event.key.toLowerCase() === "f") {
      event.preventDefault()
      event.stopImmediatePropagation()
      return this.#toggleFavorite()
    }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      event.stopImmediatePropagation()
      return this.#move(event.key === "ArrowDown" ? 1 : -1)
    }
    // While a key input is OPEN, Enter belongs to it alone (its own
    // keydown.enter action submits the key) — the row handler stays out.
    if (event.key === "Enter" && !this.#openKeyInput()) {
      const selected = this.#selectedRow()
      if (selected) {
        event.preventDefault()
        event.stopImmediatePropagation()
        this.#enter(selected)
      }
    }
  }

  // The revealed (visible) key input, if any — at most one is ever open.
  // Presence-based rather than focus-based: document.activeElement is not a
  // reliable signal across environments.
  #openKeyInput() {
    return this.keyInputTargets.find((i) => !i.hidden)
  }

  // Escape while an API-key input is open: back out to the list, don't close —
  // the staged dismiss keeps a mistyped paste recoverable.
  #hideKeyInput(input) {
    input.value  = ""
    input.hidden = true
    this.searchTarget.focus()
  }

  async #enter(row) {
    switch (row.dataset.rowType) {
      case "model":   return this.#pick(row)
      case "connect": return this.#revealKeyInput(row.dataset.provider)
      case "effort":  return this.#cycleEffort(row)
    }
  }

  async #pick(row) {
    const provider = row.dataset.provider
    const model    = row.dataset.value
    const response = await this.#request({ provider, model })
    if (response && response.status === 422) return this.#flash("unknown model")
    if (!response || !response.ok) return this.#flash("could not save model")

    this.rowTargets.forEach((r) => {
      if (r.dataset.rowType !== "model") return
      const marker = r.querySelector("span")
      if (marker) marker.textContent = (r === row || (r.dataset.provider === provider && r.dataset.value === model)) ? "●" : ""
    })
    this.#flash(`model saved: ${provider}/${model}`)
  }

  #revealKeyInput(provider) {
    const input = this.keyInputTargets.find((i) => i.dataset.provider === provider)
    if (!input) return

    const open = this.#openKeyInput()
    if (open && open !== input) this.#hideKeyInput(open) // one open entry at a time

    input.hidden = false
    input.focus()
  }

  async #cycleEffort(row) {
    const current = row.dataset.value || "off"
    const next    = EFFORT_CYCLE[(EFFORT_CYCLE.indexOf(current) + 1) % EFFORT_CYCLE.length]
    const response = await this.#request({ effort: next })
    if (!response || !response.ok) return this.#flash("could not set effort")

    row.dataset.value = next
    if (this.hasEffortValueTarget) this.effortValueTarget.textContent = next === "off" ? "model default" : next
    this.#flash(`effort: ${next}`)
  }

  async #toggleFavorite() {
    const row = this.#selectedRow()
    if (!row || row.dataset.rowType !== "model") return

    const entry    = `${row.dataset.provider}/${row.dataset.value}`
    const response = await this.#request({ favorite: entry })
    if (!response || !response.ok) return this.#flash("could not toggle favorite")

    this.#flash(`favorite toggled: ${entry} (reopen to regroup)`)
  }

  async #clearKey() {
    const row = this.#selectedRow()
    if (!row) return

    const provider = row.dataset.provider
    const response = await this.#request({ provider, clear_key: true })
    if (!response || !response.ok) return this.#flash("could not clear key")

    this.#setChip(provider, false)
    this.#connectRow(provider)?.removeAttribute("hidden")
    this.#flash(`${provider} key cleared`)
  }

  #connectRow(provider) {
    return this.rowTargets.find((r) => r.dataset.rowType === "connect" && r.dataset.provider === provider)
  }

  #setChip(provider, present) {
    const chip = this.keyChipTargets.find((c) => c.dataset.provider === provider)
    if (!chip) return

    chip.innerHTML = present
      ? '<span class="text-fg-dim">key</span> <span class="text-pito">●●●●</span>'
      : '<span class="text-fg-faded">no key</span>'
  }

  #move(step) {
    const rows = this.#visibleRows()
    if (rows.length === 0) return

    const current = rows.indexOf(this.#selectedRow())
    const next    = current === -1 ? 0 : Math.min(Math.max(current + step, 0), rows.length - 1)
    this.#select(rows[next])
  }

  #select(row) {
    this.rowTargets.forEach((r) => r.classList.remove("pito-palette-selected"))
    if (!row) return

    row.classList.add("pito-palette-selected")
    row.scrollIntoView({ block: "nearest" })
  }

  #selectedRow() {
    return this.rowTargets.find((r) => r.classList.contains("pito-palette-selected")) || null
  }

  #visibleRows() {
    return this.rowTargets.filter((r) => !r.hidden)
  }

  // PATCH /settings/ai. Returns the Response, or null on a network failure.
  async #request(fields) {
    try {
      return await fetch(this.endpointValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept":       "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify(fields)
      })
    } catch {
      return null
    }
  }

  #flash(text) {
    clearTimeout(this.statusTimer)
    this.statusTarget.textContent = text
    this.statusTimer = setTimeout(() => { this.statusTarget.textContent = "" }, STATUS_FLASH_MS)
  }
}
