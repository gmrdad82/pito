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

    this.#itemEls().forEach((el, i) => {
      const match = this.#fuzzy(query, el.dataset.label || "")
      el.classList.toggle("hidden", !match)
      if (match && firstVisible === -1) firstVisible = i
    })

    this.#syncSectionVisibility()
    this.#setSelected(firstVisible)
  }

  // Mouse hover over a row: mirror the keyboard selection onto the hovered row
  // so mouse and keyboard selection never disagree.
  hover(event) {
    const index = this.#visibleItems().indexOf(event.currentTarget)
    if (index !== -1) this.#setSelected(index)
  }

  // Mouse click on a row: select + activate it — identical to arrow-to that row
  // then Enter (same #setSelected + #commit path).
  select(event) {
    const index = this.#visibleItems().indexOf(event.currentTarget)
    if (index === -1) return
    this.#setSelected(index)
    this.#commit()
  }

  // ── internals ──────────────────────────────────────────────────────────────

  // ctrl+/ toggles the notifications panel: if it's already showing, close it;
  // otherwise open it (replacing whatever the sidebar held).
  #toggleNotifications() {
    const sidebar = document.getElementById("pito-sidebar")
    if (sidebar && sidebar.querySelector(".pito-notification-row")) {
      sidebar.innerHTML = ""
      localStorage.removeItem("pito:sidebar")
      return
    }
    this.#openNotifications()
  }

  #openNotifications() {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    fetch("/notifications", {
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrf
      }
    })
      .then(r => r.text())
      .then(html => window.Turbo.renderStreamMessage(html))
      .catch(err => console.warn("[pito] notifications fetch failed:", err))
  }

  // Ctrl+n — open the conversations sidebar (showing the current conversation
  // highlighted) and start an inline rename on it.
  //
  // Timing: the sidebar is rendered via a Turbo Stream fetch so the DOM isn't
  // ready immediately. We use a MutationObserver on #pito-sidebar to wait for
  // the `.is-current` row to appear, then dispatch `pito:rename:start` on it.
  // The observer is disconnected once the row is found (or after a short
  // timeout so we never leak).
  #renameCurrentConversation() {
    const m = location.pathname.match(/\/chat\/([0-9a-f-]+)/i)
    if (!m) return // not on a conversation page — no-op

    const uuid = m[1]
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""

    // If the sidebar already shows the conversation list, skip the fetch and
    // just find + trigger the current row directly.
    const sidebar = document.getElementById("pito-sidebar")
    if (sidebar && sidebar.querySelector(".pito-conversation-row")) {
      this.#triggerRenameOnCurrentRow(sidebar)
      return
    }

    fetch(`/resume?uuid=${uuid}`, {
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrf
      }
    })
      .then(r => r.text())
      .then(html => {
        window.Turbo.renderStreamMessage(html)
        // Wait for the sidebar DOM to contain the current row, then rename.
        this.#waitForCurrentRow(sidebar || document.getElementById("pito-sidebar"))
      })
      .catch(err => console.warn("[pito] rename-current fetch failed:", err))
  }

  // Dispatch `pito:rename:start` on the `.is-current` conversation row.
  // Called when the row is already present in the sidebar.
  #triggerRenameOnCurrentRow(sidebar) {
    const row = sidebar.querySelector(".pito-conversation-row.is-current")
    if (row) row.dispatchEvent(new CustomEvent("pito:rename:start"))
  }

  // Use a MutationObserver to wait for `.pito-conversation-row.is-current`
  // to appear inside the sidebar element, then fire the rename event.
  // Gives up after ~2 s (20 × 100 ms) to avoid leaking observers.
  #waitForCurrentRow(sidebar) {
    if (!sidebar) return
    let attempts = 0
    const MAX = 20

    const tryNow = () => {
      const row = sidebar.querySelector(".pito-conversation-row.is-current")
      if (row) { row.dispatchEvent(new CustomEvent("pito:rename:start")); return true }
      return false
    }

    if (tryNow()) return

    const observer = new MutationObserver(() => {
      attempts++
      if (tryNow() || attempts >= MAX) observer.disconnect()
    })
    observer.observe(sidebar, { childList: true, subtree: true })

    // Safety net: disconnect after 2 s even if no rows ever appear.
    setTimeout(() => observer.disconnect(), 2000)
  }

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
    // Scroll selected item into view (jsdom has no layout engine, so the method
    // may be absent — guard it so transient picker items don't throw).
    visible[next]?.scrollIntoView?.({ block: "nearest" })
  }

  #setSelected(index) {
    const visible = this.#visibleItems()
    this.selectedIndex = index

    this.#itemEls().forEach(el => el.classList.remove(SELECTED_CLASS))
    if (index >= 0 && index < visible.length) {
      visible[index].classList.add(SELECTED_CLASS)
    }
  }

  // Item elements in document order. We query the DOM rather than read
  // `this.itemTargets` so transient items injected by the hashtag picker
  // are seen synchronously, without waiting for Stimulus to re-scan targets.
  #itemEls() {
    return Array.from(
      this.element.querySelectorAll('[data-pito--command-palette-target="item"]')
    )
  }

  #visibleItems() {
    return this.#itemEls().filter(el => !el.classList.contains("hidden"))
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
    // Ctrl+K (or Cmd+K on Mac) → toggle command palette
    const modKey = e.ctrlKey || e.metaKey
    if (modKey && e.key === "k") {
      e.preventDefault()
      if (!isAuthenticated()) return
      this.element.classList.contains("hidden") ? this.#open() : this.#close()
      return
    }

    // Ctrl+/ (or Cmd+/ on Mac) → toggle notifications sidebar
    if (modKey && e.key === "/") {
      e.preventDefault()
      if (!isAuthenticated()) return
      this.#toggleNotifications()
      return
    }

    // Ctrl+n (or Cmd+n on Mac) → open sidebar and start renaming current conversation
    if (modKey && e.key === "n") {
      e.preventDefault()
      if (!isAuthenticated()) return
      this.#renameCurrentConversation()
      return
    }

    // "m" → when palette is closed and focus is not in an input: dismiss any open
    //   sidebar AND focus the chatbox (works for authenticated + unauthenticated;
    //   auth gate removed). Esc dismisses without focusing (resume_controller).
    if (e.key === "m" && !modKey && this.element.classList.contains("hidden")) {
      const active = document.activeElement
      const isInput = active && (
        active.tagName === "INPUT" ||
        active.tagName === "TEXTAREA" ||
        active.isContentEditable
      )
      if (!isInput) {
        e.preventDefault()
        if (document.querySelector("#pito-sidebar aside")) {
          window.dispatchEvent(new CustomEvent("pito:resume:dismiss"))
        }
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
