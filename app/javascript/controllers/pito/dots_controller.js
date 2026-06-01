// Pito::DotsController
//
// Shows the PostCommandDots comet when a command is submitted and hides it
// when the RESULT segment arrives (not the echo).
//
// Lifecycle:
//   submit        → dots appear fast  (backend is working)
//   echo arrives  → dots STAY (echo just means "received"; still evaluating)
//   result arrives → dots fade out slow (evaluation complete)
//
// 1:4 ratio (150ms fade-in, 600ms fade-out) — see CSS.
//
// Listens to document events dispatched by:
//   chat-form  → "pito:submitted"      (command sent — show dots)
//   scrollback → "pito:result-appended" (result landed — hide dots)
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

    // Submit → show (backend working); result arrives → hide (evaluation done).
    // Echo does NOT hide the dots — it only confirms the command was received.
    document.addEventListener("pito:submitted",      () => this.#show(), { signal })
    document.addEventListener("pito:result-appended", () => this.#hide(), { signal })
  }

  disconnect() {
    this.abort?.abort()
  }

  #show() { this.element.classList.remove("pito-dots--hidden") }
  #hide() { this.element.classList.add("pito-dots--hidden") }
}
