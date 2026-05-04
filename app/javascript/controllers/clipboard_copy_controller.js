import { Controller } from "@hotwired/stimulus"

// Item 1 — Code-block component with [ copy ] button.
// Reads textContent from the source target, writes to clipboard via the
// async navigator.clipboard API (NOT alert/confirm/prompt — those are
// banned by the Pito hard rules), then dispatches a top-right toast
// notice ("paste it in your terminal.") via the existing toast surface.
// Stimulus's MutationObserver picks up the injected `data-controller`
// attribute and connects the toast controller, which handles
// auto-dismiss + click-to-dismiss.
export default class extends Controller {
  static targets = ["source"]
  static values = {
    toastMessage: { type: String, default: "paste it in your terminal." }
  }

  copy(event) {
    event.preventDefault()
    const text = this.sourceTarget.textContent.trim()
    navigator.clipboard.writeText(text).then(() => {
      this._flashToast(this.toastMessageValue)
    })
  }

  _flashToast(message) {
    const container = document.querySelector(".toast-container")
    if (!container) return
    const toast = document.createElement("div")
    toast.className = "toast toast-notice"
    toast.textContent = message
    toast.setAttribute("data-controller", "toast")
    container.appendChild(toast)
  }
}
