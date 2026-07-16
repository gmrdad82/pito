import { Controller } from "@hotwired/stimulus"

// FX debug FPS meter — the F9-toggled chip's readout, every environment
// (3.0.0; it used to live dev-only inside the DEVELOPMENT ribbon — that's
// gone, the chip is the new home). Two sources, one display:
//
//   1. Until the fx engine exists (or when it is off), sample the page's own
//      requestAnimationFrame cadence over 500ms windows — the honest "what
//      the browser achieves" number.
//   2. The fx engine broadcasts `pito:fx:fps` custom events (detail.fps, its
//      own 30fps-capped clock). While those arrive (freshness window 1s),
//      they win over the rAF sample: `<raf> fps · fx <engine>`.
//
// Visibility-gated (owner: an untoggled chip must cost zero rAF work, not
// "runs but skips work") — an IntersectionObserver on this.element starts/
// stops the sampling loop as the `.pito-fps-overlay` wrapper's `hidden`
// class flips (pito--fps-overlay's F9 toggle). No polling: the observer
// fires on the ancestor class flip itself. Counters reset on every #start
// so a freshly-revealed chip's first window is never polluted by the hidden
// gap. jsdom has no IntersectionObserver — fall back to sampling
// unconditionally on connect so specs can still drive #start/#stop directly.
//
// The `pito:fx:fps` listener stays attached for the controller's whole
// lifetime regardless of visibility — it's cheap (an event, not a loop) and
// keeps `_engineFps` warm for whenever sampling resumes.
//
// The meter is display-only chrome: no layout writes, pointer-events none
// via the wrapper, self-cleaning on disconnect.
export default class extends Controller {
  connect() {
    this._engineFps = null
    this._engineSeenAt = 0
    this._running = false
    this._raf = null

    this._onEngineFps = (e) => {
      this._engineFps = Math.round(e.detail?.fps ?? 0)
      this._engineSeenAt = performance.now()
    }
    window.addEventListener("pito:fx:fps", this._onEngineFps)

    this._tick = (now) => {
      if (!this._running) return
      this._raf = requestAnimationFrame(this._tick)
      this._frames++
      if (now - this._windowStart >= 500) {
        const rafFps = Math.round((this._frames * 1000) / (now - this._windowStart))
        this._frames = 0
        this._windowStart = now
        const engineFresh = now - this._engineSeenAt < 1000
        this.element.textContent = engineFresh
          ? `${rafFps} fps · fx ${this._engineFps}`
          : `${rafFps} fps`
      }
    }

    if (typeof IntersectionObserver === "undefined") {
      this.#start()
      return
    }
    this._io = new IntersectionObserver((entries) => {
      const visible = entries.some((entry) => entry.isIntersecting)
      visible ? this.#start() : this.#stop()
    })
    this._io.observe(this.element)
  }

  disconnect() {
    this._io?.disconnect()
    this.#stop()
    window.removeEventListener("pito:fx:fps", this._onEngineFps)
  }

  #start() {
    if (this._running) return
    this._running = true
    this._frames = 0
    this._windowStart = performance.now()
    this._raf = requestAnimationFrame(this._tick)
  }

  #stop() {
    this._running = false
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = null
  }
}
