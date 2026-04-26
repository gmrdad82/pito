import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]
  static values = {
    title: { type: String, default: "Are you sure?" },
    message: { type: String, default: "" }
  }

  open(event) {
    event.preventDefault()
    this.dialogTarget.querySelector("[data-role='title']").textContent = this.titleValue
    const messageEl = this.dialogTarget.querySelector("[data-role='message']")
    if (messageEl) messageEl.textContent = this.messageValue
    this.dialogTarget.showModal()
  }

  confirm() {
    this.dialogTarget.close("confirm")
    this.dispatch("confirmed")
  }

  cancel() {
    this.dialogTarget.close("cancel")
  }

  clickOutside(event) {
    if (event.target === this.dialogTarget) {
      this.cancel()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.cancel()
    }
  }
}
