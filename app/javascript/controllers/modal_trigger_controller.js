import { Controller } from "@hotwired/stimulus"

// Opens a dialog (or any element with .showModal()) by its DOM id.
// Usage on a link/button:
//   data-controller="modal-trigger"
//   data-action="click->modal-trigger#open"
//   data-modal-trigger-target-id-value="confirm-saved-view-42"
export default class extends Controller {
  static values = { targetId: String }

  open(event) {
    if (event) event.preventDefault()
    const target = document.getElementById(this.targetIdValue)
    if (target && typeof target.showModal === "function") {
      target.showModal()
    }
  }
}
