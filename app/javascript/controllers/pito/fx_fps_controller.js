import { Controller } from "@hotwired/stimulus"

// FX debug FPS meter (dev-only — it only exists inside the DEVELOPMENT
// ribbon). Two sources, one display:
//
//   1. Until the fx engine exists (or when it is off), sample the page's own
//      requestAnimationFrame cadence over 500ms windows — the honest "what
//      the browser achieves" number.
//   2. The fx engine broadcasts `pito:fx:fps` custom events (detail.fps, its
//      own 30fps-capped clock). While those arrive (freshness window 1s),
//      they win over the rAF sample: `<raf> fps · fx <engine>`.
//
// The meter is display-only chrome: no layout writes, pointer-events none
// via the ribbon, self-cleaning on disconnect.
export default class extends Controller {
  connect() {
    this._frames = 0
    this._windowStart = performance.now()
    this._engineFps = null
    this._engineSeenAt = 0
    this._raf = null

    this._onEngineFps = (e) => {
      this._engineFps = Math.round(e.detail?.fps ?? 0)
      this._engineSeenAt = performance.now()
    }
    window.addEventListener("pito:fx:fps", this._onEngineFps)

    const tick = (now) => {
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
      this._raf = requestAnimationFrame(tick)
    }
    this._raf = requestAnimationFrame(tick)
  }

  disconnect() {
    if (this._raf) cancelAnimationFrame(this._raf)
    window.removeEventListener("pito:fx:fps", this._onEngineFps)
  }
}
