import { Controller } from "@hotwired/stimulus"
import { fxEnabled } from "pito/settings"

// Gates the sidebar's open/close WIDTH animation on `/config fx`.
//   fx on  → the sidebar animates (Tailwind `transition-[width] duration-200`).
//   fx off → it snaps instantly (the `pito-sidebar--no-anim` class kills the
//            transition).
// Also respects `prefers-reduced-motion`. Re-evaluates live when #pito-settings
// changes — a `/config fx on|off` broadcast replaces that element's data-fx, so
// the sidebar flips behaviour without a reload.
export default class extends Controller {
  connect() {
    this._apply()

    const settings = document.getElementById("pito-settings")
    if (settings) {
      this._observer = new MutationObserver(() => this._apply())
      this._observer.observe(settings, { attributes: true, attributeFilter: ["data-fx"] })
    }
  }

  disconnect() {
    this._observer?.disconnect()
  }

  _apply() {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.classList.toggle("pito-sidebar--no-anim", reduce || !fxEnabled())
  }
}
