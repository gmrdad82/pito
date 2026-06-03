// Pito::ChatFormController
//
// Stimulus controller for the terminal chatbox form.
// Captures Enter (no Shift) on the input target → submits via Turbo, clears input.
//
// Targets:
//   inputField  — the <textarea> (data-pito--chat-form-target="inputField")
//                 Must also carry data-action="keydown->pito--chat-form#handleKeydown"
//   hiddenInput — a hidden <input> whose value gets set before submit
//                 (so the Rails controller receives params[:input])
//
// The controller lives on the <form> element — use this.element for the form itself.
// Enter submits the form; Shift+Enter passes through for multi-line potential.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inputField", "hiddenInput"]

  connect() {
    this.#syncHidden()
  }

  // Click anywhere on the chatbox wrapper → focus the textarea
  focusField(event) {
    // Only focus if the click wasn't directly on the textarea (it already handles itself)
    if (event.target !== this.inputFieldTarget) {
      this.inputFieldTarget.focus({ preventScroll: true })
    }
  }

  handleKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return

    // Cable dead after inactivity — reload to re-establish the WebSocket
    // before submitting. Without this, the POST succeeds but Turbo Stream
    // broadcasts never reach the client and the page appears stuck.
    if (document.body.dataset.pitoCableOffline === "true") {
      event.preventDefault()
      window.location.reload()
      return
    }

    const hasInput = this.inputFieldTarget.value.trim().length > 0
    event.preventDefault()
    this.#syncHidden()
    this.element.requestSubmit()
    this.inputFieldTarget.value = ""
    this.inputFieldTarget.dispatchEvent(new Event("input", { bubbles: true }))

    // Only signal "submitted" when there is actual input — empty Enter is silent.
    if (hasInput) {
      document.dispatchEvent(new CustomEvent("pito:submitted"))
    }
  }

  #syncHidden() {
    this.hiddenInputTarget.value = this.inputFieldTarget.value
  }
}
