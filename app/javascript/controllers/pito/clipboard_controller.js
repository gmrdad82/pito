import { Controller } from "@hotwired/stimulus"

// Copies text to the clipboard on click or keyboard shortcut.
//
// Data attributes:
//   data-clipboard-text-value="text to copy"
//
// Targets:
//   data-clipboard-target="feedback" — element whose text changes to
//   "Copied!" briefly after a successful copy.
export default class extends Controller {
  static values = { text: String }
  static targets = ["feedback"]

  copy() {
    if (!this.textValue) return

    navigator.clipboard.writeText(this.textValue).then(() => {
      this.flashFeedback()
    }).catch(() => {
      // Fallback for environments without clipboard API
      this.fallbackCopy()
    })
  }

  flashFeedback() {
    const original = this.feedbackTarget.textContent
    this.feedbackTarget.textContent = "Copied!"
    this.feedbackTarget.classList.add("text-success")

    setTimeout(() => {
      this.feedbackTarget.textContent = original
      this.feedbackTarget.classList.remove("text-success")
    }, 1500)
  }

  fallbackCopy() {
    const textarea = document.createElement("textarea")
    textarea.value = this.textValue
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()

    try {
      document.execCommand("copy")
      this.flashFeedback()
    } catch (_err) {
      // silently fail
    } finally {
      document.body.removeChild(textarea)
    }
  }
}
