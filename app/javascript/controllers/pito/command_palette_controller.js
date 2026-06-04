// pito--command-palette
//
// Ctrl+K → open · Esc → close · ↑↓ → navigate · Enter → insert + close.
//
// Enter pre-fills the chatbox textarea with the selected command (including
// <placeholder> markers) but does NOT submit — the user fills in arguments
// and hits Enter themselves.
//
// Fuzzy search: all characters of the query must appear in the item label in
// order (standard subsequence match, case-insensitive). Empty query → all
// items visible.
//
// Markup (in application layout, hidden by default):
//   <div id="pito-command-palette"
//        data-controller="pito--command-palette"
//        class="hidden fixed inset-0 z-50 flex items-center justify-center ...">
//     <div><!-- CtrlK::Component --></div>
//   </div>

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"

const SELECTED_CLASS = "pito-palette-selected"

export default class extends Controller {
  static targets = ["search", "item", "section", "sectionTitle", "sectionGap", "list"]

  connect() {
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onGlobalKey.bind(this),
      { signal: this.abort.signal })
    this.selectedIndex = -1
  }

  disconnect() {
    this.abort?.abort()
  }

  // ── Public actions (wired via data-action) ─────────────────────────────────

  filter() {
    const query = this.searchTarget.value.trim()
    let firstVisible = -1

    this.itemTargets.forEach((el, i) => {
      const match = this.#fuzzy(query, el.dataset.label || "")
      el.classList.toggle("hidden", !match)
      if (match && firstVisible === -1) firstVisible = i
    })

    this.#syncSectionVisibility()
    this.#setSelected(firstVisible)
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #open() {
    this.element.classList.remove("hidden")
    this.searchTarget.value = ""
    this.filter()                    // reset item visibility
    this.#setSelected(0)             // select first visible item
    this.searchTarget.focus()
  }

  #close() {
    this.element.classList.add("hidden")
    this.selectedIndex = -1
  }

  #commit() {
    const el = this.#visibleItems()[this.selectedIndex]
    if (!el) return

    const chatbox = document.querySelector('[data-pito--chat-form-target="inputField"]')
    if (chatbox) {
      chatbox.value = el.dataset.insert || ""
      chatbox.dispatchEvent(new Event("input", { bubbles: true }))
      chatbox.focus()
      // Place cursor at end
      chatbox.selectionStart = chatbox.selectionEnd = chatbox.value.length
    }
    this.#close()
  }

  #move(delta) {
    const visible = this.#visibleItems()
    if (!visible.length) return
    const next = Math.max(0, Math.min(visible.length - 1,
      (this.selectedIndex === -1 ? 0 : this.selectedIndex) + delta))
    this.#setSelected(next)
    // Scroll selected item into view
    visible[next]?.scrollIntoView({ block: "nearest" })
  }

  #setSelected(index) {
    const visible = this.#visibleItems()
    this.selectedIndex = index

    this.itemTargets.forEach(el => el.classList.remove(SELECTED_CLASS))
    if (index >= 0 && index < visible.length) {
      visible[index].classList.add(SELECTED_CLASS)
    }
  }

  #visibleItems() {
    return this.itemTargets.filter(el => !el.classList.contains("hidden"))
  }

  #syncSectionVisibility() {
    if (!this.hasSectionTarget) return
    this.sectionTargets.forEach(section => {
      const items   = section.querySelectorAll('[data-pito--command-palette-target="item"]')
      const anyVisible = Array.from(items).some(el => !el.classList.contains("hidden"))
      section.classList.toggle("hidden", !anyVisible)
    })
    // Hide section-gap divs between now-hidden sections
    if (this.hasSectionGapTarget) {
      this.sectionGapTargets.forEach(gap => gap.classList.remove("hidden"))
    }
  }

  // Standard subsequence (fuzzy) match: all query chars appear in text in order.
  #fuzzy(query, text) {
    if (!query) return true
    const q = query.toLowerCase()
    const t = text.toLowerCase()
    let qi = 0
    for (let i = 0; i < t.length && qi < q.length; i++) {
      if (t[i] === q[qi]) qi++
    }
    return qi === q.length
  }

  #onGlobalKey(e) {
    // Ctrl+K (or Cmd+K on Mac) → toggle
    const modKey = e.ctrlKey || e.metaKey
    if (modKey && e.key === "k") {
      e.preventDefault()
      if (!isAuthenticated()) return
      this.element.classList.contains("hidden") ? this.#open() : this.#close()
      return
    }

    // "m" → focus chatbox textarea (when palette is closed and not already in an input)
    if (e.key === "m" && !modKey && this.element.classList.contains("hidden")) {
      const active = document.activeElement
      const isInput = active && (
        active.tagName === "INPUT" ||
        active.tagName === "TEXTAREA" ||
        active.isContentEditable
      )
      if (!isInput && isAuthenticated()) {
        e.preventDefault()
        const chatbox = document.querySelector('[data-pito--chat-form-target="inputField"]')
        if (chatbox) {
          chatbox.focus({ preventScroll: true })
          chatbox.selectionStart = chatbox.selectionEnd = chatbox.value.length
        }
      }
      return
    }

    // Only handle the rest when palette is open
    if (this.element.classList.contains("hidden")) return

    if (e.key === "Escape") { e.preventDefault(); this.#close() }
    else if (e.key === "ArrowDown") { e.preventDefault(); this.#move(1) }
    else if (e.key === "ArrowUp")   { e.preventDefault(); this.#move(-1) }
    else if (e.key === "Enter")     { e.preventDefault(); this.#commit() }
  }
}
