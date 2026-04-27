import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  onKeydown(event) {
    if (event.target.matches("input, textarea, select, [contenteditable]")) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (event.key === "?") {
      event.preventDefault()
      this.dialogTarget.showModal()
    } else if (event.key === "/" ) {
      event.preventDefault()
      const input = document.querySelector(".search-input")
      if (input) input.focus()
    } else if (event.key === "Escape" && this.dialogTarget.open) {
      this.dialogTarget.close()
    }
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
