// Pito::TurnCompleteController
//
// Dispatches `pito:turn-complete` on connect. Used to signal that a
// multi-stage turn is fully finished (all events emitted, thinking
// resolved). Attached to the resolved-thinking element so the event
// fires when Turbo replaces the spinner with the resolved message.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    document.dispatchEvent(new CustomEvent("pito:turn-complete", {
      bubbles: true
    }))
  }
}
