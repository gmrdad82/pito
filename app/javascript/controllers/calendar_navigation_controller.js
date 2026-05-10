import { Controller } from "@hotwired/stimulus"

// Phase 15 §2 — keyboard shortcuts for the month grid:
//   `[` → prev month
//   `]` → next month
//   `t` → today
//
// Bindings are gated when focus sits inside an input / textarea / select
// / contenteditable, mirroring the global keyboard controller's
// "search overlay swallows keys" rule.
export default class extends Controller {
  static values = {
    prevUrl: String,
    nextUrl: String,
    todayUrl: String
  }

  connect() {
    this.boundHandler = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandler)
  }

  handleKey(event) {
    if (this.isTypingTarget(event.target)) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    switch (event.key) {
      case "[":
        event.preventDefault()
        if (this.prevUrlValue) window.location.assign(this.prevUrlValue)
        break
      case "]":
        event.preventDefault()
        if (this.nextUrlValue) window.location.assign(this.nextUrlValue)
        break
      case "t":
        event.preventDefault()
        if (this.todayUrlValue) window.location.assign(this.todayUrlValue)
        break
    }
  }

  isTypingTarget(el) {
    if (!el) return false
    const tag = el.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true
    if (el.isContentEditable) return true
    return false
  }
}
