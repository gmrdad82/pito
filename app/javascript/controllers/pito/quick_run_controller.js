// pito--quick-run
//
// Attached to the scrollback container. Listens globally for ctrl+/ and
// populates the chatbox with the command from the LAST [data-suggestion-command]
// element in the scrollback — mirroring how ctrl+| (expand) applies to the last
// expandable segment.

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"

export default class extends Controller {
  connect() {
    this._onKeydown = this.#populate.bind(this)
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  #populate(event) {
    if (!event.ctrlKey || event.key !== "/") return
    if (!isAuthenticated()) return
    const suggestions = this.element.querySelectorAll("[data-suggestion-command]")
    const last = suggestions[suggestions.length - 1]
    if (!last) return
    event.preventDefault()
    const input = document.querySelector('[data-pito--chat-form-target="inputField"]')
    if (!input) return
    input.value = last.dataset.suggestionCommand
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.focus({ preventScroll: true })
  }
}
