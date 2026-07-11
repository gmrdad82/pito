// Pito::DotsController
//
// Shows the PostCommandDots comet when a command is submitted and hides it the
// instant the response lands — when the first result segment appears (messages
// render instantly now; there is no echo-typing phase).
//
// Lifecycle:
//   submit               → dots appear fast (command sent — backend is working)
//   pito:result-appended → dots fade out slow (a result landed — hide dots)
//
// No-result / sidebar fast paths:
//   A /slash command that only opens a sidebar (/resume, /themes, the game /
//   video pickers, IGDB import) produces no scrollback result, so
//   pito:result-appended never arrives. The sidebar dispatches "pito:comet-clear"
//   on open (resume_controller) so the comet doesn't hang. (#hide is idempotent.)
//
// 1:4 ratio (150ms fade-in, 600ms fade-out) — see CSS.
//
// Listens to document events dispatched by:
//   chat-form   → "pito:submitted"       (command sent — show dots)
//   scrollback  → "pito:result-appended" (a result landed — hide dots)
//   resume      → "pito:comet-clear"     (sidebar/client-only command — hide dots)
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

    document.addEventListener("pito:submitted",       () => this.#show(), { signal })
    document.addEventListener("pito:result-appended", () => this.#hide(), { signal })
    document.addEventListener("pito:comet-clear",     () => this.#hide(), { signal })
  }

  disconnect() {
    this.abort?.abort()
  }

  #show() { this.element.classList.remove("pito-dots--hidden") }
  #hide() { this.element.classList.add("pito-dots--hidden") }
}
