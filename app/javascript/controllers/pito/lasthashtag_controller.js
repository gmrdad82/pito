// Pito::LasthashtagController
//
// Paints the `· shift+r` affordance on ONLY the most recent hashtag-bearing
// segment in the scrollback. As new hashtag messages stream in (cable appends),
// the hint hops to the latest segment and is removed from the previous one.
//
// shift+r itself is handled by pito--chat-form: when the caret sits at the
// start of the chatbox it prepends `#<handle> ` using the same last handle.
//
// Mounted on the scrollback container so its MutationObserver sees live appends.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._refresh = () => this.#refresh()
    this._observer = new MutationObserver(() => this.#schedule())
    this._observer.observe(this.element, { childList: true, subtree: true })
    this.#refresh()
  }

  disconnect() {
    this._observer?.disconnect()
    if (this._raf) cancelAnimationFrame(this._raf)
  }

  #schedule() {
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = requestAnimationFrame(this._refresh)
  }

  // Show the hint on the last segment that has one, hide it everywhere else.
  // Toggling a class fires only `attributes` mutations, which the observer
  // ignores (childList only), so there is no feedback loop.
  #refresh() {
    const hints = this.element.querySelectorAll("[data-pito-lasthashtag-hint]")
    const last = hints.length - 1
    hints.forEach((hint, i) => hint.classList.toggle("hidden", i !== last))
  }
}
