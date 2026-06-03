// Pito::DoneDispatchController
//
// Dispatches a custom DOM event on connect. Used by the broadcaster to
// signal turn completion (pito:done) without needing a custom Turbo
// Stream action.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    eventName: String
  }

  connect() {
    document.dispatchEvent(new CustomEvent(this.eventNameValue, {
      bubbles: true
    }))
  }
}
