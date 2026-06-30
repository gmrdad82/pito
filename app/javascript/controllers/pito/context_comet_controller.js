// pito--context-comet
//
// Context-bar "lit fuse" (item 7). On each new distinct message the fill GROWS
// from the previous % to the new %; an orange glowing head rides the leading
// edge from the old position to the new one — like a lit dynamite fuse — then
// fades (no trail, settles flat). The previous % is remembered per-conversation
// in localStorage (keyed by the path) so the grow animates across the Turbo
// Stream re-render of the meter (a fresh element each turn would otherwise jump).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fill", "comet"]
  static values  = { pct: Number }

  connect() {
    const now  = this.pctValue
    const prev = this.#prev()
    this.#store(now)

    // First render for this conversation, or no growth → render flat, no comet.
    if (prev < 0 || now <= prev || !this.hasFillTarget) return

    // Start at the OLD width / comet at the OLD edge, then grow on the next frame
    // so the CSS width/left transitions fire (the element was just re-rendered).
    this.fillTarget.style.width = `${prev}%`
    if (this.hasCometTarget) {
      this.cometTarget.style.left = `${prev}%`
      this.cometTarget.classList.add("is-lit")
    }
    this._raf = requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        this.fillTarget.style.width = `${now}%`
        if (this.hasCometTarget) this.cometTarget.style.left = `${now}%`
      })
    )
    // Fade the head once it reaches the new edge (matches the 0.6s transition).
    this._timer = setTimeout(() => {
      this.cometTarget?.classList.remove("is-lit")
    }, 700)
  }

  disconnect() {
    cancelAnimationFrame(this._raf)
    clearTimeout(this._timer)
  }

  #prev() {
    try {
      const v = localStorage.getItem(this.#key())
      return v === null ? -1 : Number(v)
    } catch (_e) { return -1 }
  }

  #store(v) {
    try { localStorage.setItem(this.#key(), String(v)) } catch (_e) { /* storage off — skip */ }
  }

  #key() {
    return `pito:ctx-pct:${location.pathname}`
  }
}
