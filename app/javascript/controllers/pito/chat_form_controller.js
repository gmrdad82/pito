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

  handleKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return

    event.preventDefault()
    this.#syncHidden()
    this.element.requestSubmit()
    this.inputFieldTarget.value = ""
  }

  #syncHidden() {
    this.hiddenInputTarget.value = this.inputFieldTarget.value
  }
}
