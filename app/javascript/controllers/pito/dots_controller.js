// Pito::DotsController
//
// Shows the PostCommandDots comet when a command is submitted and hides it
// when the turn is fully complete (pito:done).
//
// Lifecycle:
//   submit  → dots appear fast (backend is working)
//   echo    → dots STAY (echo means "received"; still evaluating)
//   pito:done → dots fade out slow (turn fully complete)
//
// 1:4 ratio (150ms fade-in, 600ms fade-out) — see CSS.
//
// Listens to document events dispatched by:
//   chat-form       → "pito:submitted" (command sent — show dots)
//   done-dispatch   → "pito:done"      (turn complete — hide dots)
//
// Usage:
//   <div data-controller="pito--dots">
//     <%= render Pito::Shell::PostCommandDotsComponent.new %>
//   </div>

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Start hidden — dots only appear while the backend is working.
    this.element.classList.add("pito-dots--hidden")

    this.abort = new AbortController()
    const { signal } = this.abort

    document.addEventListener("pito:submitted", () => this.#show(), { signal })
    document.addEventListener("pito:done",      () => this.#hide(), { signal })
  }

  disconnect() {
    this.abort?.abort()
  }

  #show() { this.element.classList.remove("pito-dots--hidden") }
  #hide() { this.element.classList.add("pito-dots--hidden") }
}
