// Pito::DotsController
//
// Shows the PostCommandDots comet when a command is submitted and hides it the
// instant the response lands — when the echoed input finishes typing, or (for
// echo-less fast paths) when the first result segment appears.
//
// Lifecycle:
//   submit          → dots appear fast (command sent — backend is working)
//   echo types out  → dots STAY while the echo reveals (still landing)
//   pito:echo-typed → dots fade out slow (the echo finished typing — landed)
//
// No-echo edge case:
//   Auth-gated fast paths broadcast an error with NO echo, NO turn, and NO
//   pito:done — so pito:echo-typed never comes. pito:result-appended (fired by
//   scrollback_controller when the error segment appends) hides the comet so it
//   never hangs. Net: the comet hides on whichever of pito:echo-typed /
//   pito:result-appended arrives first (both #hide calls are idempotent).
//
//   pito:done still fires elsewhere (completed_at / resume) but no longer drives
//   the comet.
//
// 1:4 ratio (150ms fade-in, 600ms fade-out) — see CSS.
//
// Listens to document events dispatched by:
//   chat-form   → "pito:submitted"       (command sent — show dots)
//   typewriter  → "pito:echo-typed"      (echo finished typing — hide dots)
//   scrollback  → "pito:result-appended" (a result landed — hide dots)
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
    document.addEventListener("pito:echo-typed",      () => this.#hide(), { signal })
    document.addEventListener("pito:result-appended", () => this.#hide(), { signal })
  }

  disconnect() {
    this.abort?.abort()
  }

  #show() { this.element.classList.remove("pito-dots--hidden") }
  #hide() { this.element.classList.add("pito-dots--hidden") }
}
