import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
  }

  clickOutside(event) {
    if (event.target === this.dialogTarget) {
      this.dialogTarget.close()
    }
  }
}
