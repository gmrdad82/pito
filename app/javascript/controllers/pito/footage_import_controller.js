import { Controller } from "@hotwired/stimulus"

// Handles the footage import probe command block.
//
// - Click on the block copies the command for THAT block.
// - Alt+C copies the LAST import block in the document (most recent `import` result).
// - On copy, a random witty overlay message flashes briefly over the block.
//
// Data attributes:
//   data-pito--footage-import-command-value  — the full probe command string
//   data-pito--footage-import-feedback-value — JSON array of witty copy messages
//
// Targets:
//   data-pito--footage-import-target="overlay" — the hidden overlay element
export default class extends Controller {
  static values = { command: String, feedback: Array }
  static targets = ["overlay"]

  connect() {
    this._keyHandler = this._onKeydown.bind(this)
    window.addEventListener("keydown", this._keyHandler)
  }

  disconnect() {
    window.removeEventListener("keydown", this._keyHandler)
  }

  copy() {
    if (!this.commandValue) return

    navigator.clipboard.writeText(this.commandValue).then(() => {
      this.flash()
    }).catch(() => {
      this._fallbackCopy()
    })
  }

  flash() {
    const variants = this.feedbackValue && this.feedbackValue.length > 0
      ? this.feedbackValue
      : ["Copied"]
    const text = variants[Math.floor(Math.random() * variants.length)]

    this.overlayTarget.textContent = text
    this.overlayTarget.classList.remove("hidden")

    setTimeout(() => {
      this.overlayTarget.classList.add("hidden")
      this.overlayTarget.textContent = ""
    }, 1500)
  }

  // ── Private ────────────────────────────────────────────────────────────────

  _onKeydown(e) {
    // alt+c by physical key, so it fires regardless of the char the layout
    // maps Alt+C to (e.g. macOS produces "ç").
    if (!e.altKey || e.code !== "KeyC") return

    // Only the LAST import block in the document responds to alt+c.
    const all = document.querySelectorAll('[data-controller~="pito--footage-import"]')
    if (all.length === 0) return

    const last = all[all.length - 1]
    if (last !== this.element) return

    e.preventDefault()
    this.copy()
  }

  _fallbackCopy() {
    const textarea = document.createElement("textarea")
    textarea.value = this.commandValue
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()

    try {
      document.execCommand("copy")
      this.flash()
    } catch (_err) {
      // silently fail
    } finally {
      document.body.removeChild(textarea)
    }
  }
}
