import { Controller } from "@hotwired/stimulus"

// Floaty top-right toast notification.
//
// Each toast auto-dismisses after `delay-value` milliseconds (default 4000)
// and can be clicked to dismiss immediately. Dismissal animates out via the
// `.dismissing` CSS class (opacity + transform transition) before the element
// is removed from the DOM. The container itself (`.toast-container`) is
// rendered server-side from the flash — see `shared/_flash_toasts.html.erb`.
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
    this.boundClick = this.onClick.bind(this)
    this.element.addEventListener("click", this.boundClick)
  }

  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    this.element.removeEventListener("click", this.boundClick)
  }

  onClick(event) {
    event.preventDefault()
    this.dismiss()
  }

  dismiss() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    if (!this.element.isConnected) return
    this.element.classList.add("dismissing")
    const remove = () => {
      if (this.element.isConnected) this.element.remove()
    }
    this.element.addEventListener("transitionend", remove, { once: true })
    // Fallback in case the transitionend never fires (e.g. reduced motion,
    // element hidden) — remove after the CSS transition duration + slack.
    setTimeout(remove, 400)
  }
}
