// pito--ai-picker
//
// Drives the /config ai overlay (Pito::Ai::PickerComponent): the OpenCode-style
// model picker. The overlay is mounted on demand by a turbo stream and REMOVED
// on close — no hidden idle state. Two sections, both server-rendered, toggled
// live here after key changes:
//
//   * no key   → masked key entry; enter PATCHes { provider, api_key } and
//                flips to the model list (the key never travels back down —
//                the server only ever answers key_present).
//   * key set  → searchable model list; ↑/↓ + enter (or click) PATCHes
//                { provider, model }; ctrl+x PATCHes { provider, clear_key }.
//
// esc or a backdrop click closes. All persistence goes through
// PATCH /settings/ai (session-gated JSON).

import { Controller } from "@hotwired/stimulus"

const STATUS_FLASH_MS = 2500

export default class extends Controller {
  static values = {
    endpoint:   String,
    provider:   String,
    keyPresent: Boolean
  }

  static targets = [
    "keySection", "keyInput", "modelsSection", "search", "list", "row",
    "keyChip", "status"
  ]

  connect() {
    this.abort = new AbortController()
    window.addEventListener("keydown", (e) => this.#keydown(e), { signal: this.abort.signal })
    this.#focusEntry()
    this.#select(this.#visibleRows()[0] || null)
  }

  disconnect() {
    this.abort?.abort()
    clearTimeout(this.statusTimer)
  }

  close() {
    this.element.remove()
  }

  // ── key management ─────────────────────────────────────────────────────────

  async saveKey() {
    const key = this.keyInputTarget.value.trim()
    if (key === "") return

    const ok = await this.#patch({ api_key: key })
    if (!ok) return this.#flash("could not save key")

    this.keyPresentValue = true
    this.keyInputTarget.value = ""
    this.#applyKeyState()
    this.#flash("key saved")
  }

  async clearKey() {
    if (!this.keyPresentValue) return

    const ok = await this.#patch({ clear_key: true })
    if (!ok) return this.#flash("could not clear key")

    this.keyPresentValue = false
    this.#applyKeyState()
    this.#flash("key cleared")
  }

  // ── model list ─────────────────────────────────────────────────────────────

  filter() {
    const needle = this.searchTarget.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => {
      const id = (row.dataset.value || "").toLowerCase()
      row.hidden = needle !== "" && !id.includes(needle)
    })
    this.#select(this.#visibleRows()[0] || null)
  }

  pick(event) {
    this.#choose(event.currentTarget)
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      return this.close()
    }
    if (event.ctrlKey && event.key.toLowerCase() === "x") {
      event.preventDefault()
      return this.clearKey()
    }
    if (this.keyPresentValue && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
      event.preventDefault()
      return this.#move(event.key === "ArrowDown" ? 1 : -1)
    }
    // Enter picks the selected row — but never while typing in the key input
    // (its own keydown.enter action saves the key).
    if (event.key === "Enter" && this.keyPresentValue && document.activeElement !== this.keyInputTarget) {
      const selected = this.#selectedRow()
      if (selected) {
        event.preventDefault()
        this.#choose(selected)
      }
    }
  }

  async #choose(row) {
    const id = row.dataset.value
    if (!id) return

    const response = await this.#request({ model: id })
    if (response && response.status === 422) return this.#flash("unknown model")
    if (!response || !response.ok) return this.#flash("could not save model")

    // Move the ● marker (each row's first span) to the chosen row.
    this.rowTargets.forEach((r) => { r.querySelector("span").textContent = "" })
    row.querySelector("span").textContent = "●"
    this.#flash(`model saved: ${id}`)
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

  #applyKeyState() {
    this.keySectionTarget.hidden    = this.keyPresentValue
    this.modelsSectionTarget.hidden = !this.keyPresentValue
    this.keyChipTarget.innerHTML    = this.keyPresentValue
      ? '<span class="text-fg-dim">key</span> <span class="text-pito">●●●●</span>'
      : '<span class="text-fg-faded">no key</span>'
    this.#focusEntry()
    this.#select(this.#visibleRows()[0] || null)
  }

  #focusEntry() {
    if (this.keyPresentValue) {
      this.searchTarget.focus()
    } else {
      this.keyInputTarget.focus()
    }
  }

  async #patch(fields) {
    const response = await this.#request(fields)
    return Boolean(response && response.ok)
  }

  // PATCH /settings/ai with the provider merged in. Returns the Response, or
  // null on a network failure (callers flash their own message).
  async #request(fields) {
    try {
      return await fetch(this.endpointValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept":       "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ provider: this.providerValue, ...fields })
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
