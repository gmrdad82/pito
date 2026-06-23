// Pito::LasthashtagController
//
// Reveals the `shift+r` affordance on EVERY hashtag-bearing segment in the
// scrollback (each hint is wired to prefill its OWN `#<handle> ` on click, so
// any shown message is click-to-reply). The hint is hidden by default in the
// component (progressive enhancement); this controller unhides it, including on
// live cable appends.
//
// Keyboard shift+r is still handled by pito--chat-form: with the caret at the
// start of the chatbox it prepends `#<handle> ` using the most recent handle.
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

  // Reveal the hint on EVERY hashtag-bearing segment. Removing a class fires
  // only `attributes` mutations, which the observer ignores (childList only),
  // so there is no feedback loop.
  #refresh() {
    this.element
      .querySelectorAll("[data-pito-lasthashtag-hint]")
      .forEach((hint) => hint.classList.remove("hidden"))
  }
}
