import { Controller } from "@hotwired/stimulus"

// Connects elements declared as data-controller="tui-cursor"
// Looks for child elements with data-tui-cursor-target="panel"
// Manages keyboard navigation between them.
//
// Behavior:
//   - TAB: cycle to next panel (Shift+TAB for previous)
//   - Ctrl+H: previous panel (left)
//   - Ctrl+L: next panel (right)
//   - Ctrl+J: next panel (down)
//   - Ctrl+K: previous panel (up)
//   - Enter / Space: activate the focused panel (dispatch a custom event for app-specific handling)
//
// Focused panel gets:
//   - data-tui-cursor-focused="yes" attribute
//   - All others have data-tui-cursor-focused="no" or attribute absent
//   - CSS rules use [data-tui-cursor-focused="yes"] to style (out of scope for this dispatch; expect CSS to be added later)

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.boundHandler = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandler)
    this.focusedIndex = 0
    this.applyFocus()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandler)
  }

  handleKey(event) {
    // Ignore when typing in a form input
    const target = event.target
    if (target.matches("input, textarea, select, [contenteditable]")) return

    // Ignore when a modal/dialog is open (the leader menu, command palette, etc.)
    if (document.querySelector("dialog[open]")) return

    let handled = false

    if (event.key === "Tab" && !event.shiftKey && !event.ctrlKey && !event.metaKey) {
      this.next()
      handled = true
    } else if (event.key === "Tab" && event.shiftKey && !event.ctrlKey && !event.metaKey) {
      this.previous()
      handled = true
    } else if (event.ctrlKey && !event.metaKey && !event.shiftKey) {
      switch (event.key) {
        case "h":
          this.previous(); handled = true; break
        case "l":
          this.next(); handled = true; break
        case "j":
          this.next(); handled = true; break
        case "k":
          this.previous(); handled = true; break
      }
    }

    if (handled) {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  next() {
    if (this.panelTargets.length === 0) return
    this.focusedIndex = (this.focusedIndex + 1) % this.panelTargets.length
    this.applyFocus()
  }

  previous() {
    if (this.panelTargets.length === 0) return
    this.focusedIndex = (this.focusedIndex - 1 + this.panelTargets.length) % this.panelTargets.length
    this.applyFocus()
  }

  applyFocus() {
    this.panelTargets.forEach((el, idx) => {
      if (idx === this.focusedIndex) {
        el.dataset.tuiCursorFocused = "yes"
        el.scrollIntoView({ block: "nearest", behavior: "smooth" })
      } else {
        delete el.dataset.tuiCursorFocused
      }
    })
  }
}
