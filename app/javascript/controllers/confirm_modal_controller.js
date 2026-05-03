import { Controller } from "@hotwired/stimulus"

// Controls a single <dialog class="confirm-modal"> instance.
// The dialog element itself is `this.element`.
export default class extends Controller {
  open(event) {
    if (event) event.preventDefault()
    this.element.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    this.element.close()
  }

  clickOutside(event) {
    if (event.target === this.element) {
      this.element.close()
    }
  }

  keydown(event) {
    // The HTML <dialog> element closes on Escape natively, but we keep this
    // handler for parity and so embedded forms can't swallow the event.
    if (event.key === "Escape") {
      event.preventDefault()
      this.element.close()
    }
  }
}
