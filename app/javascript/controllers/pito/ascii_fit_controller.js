import { Controller } from "@hotwired/stimulus"

// Pito::AsciiFitController  (data-controller="pito--ascii-fit")
//
// Uniformly scales `white-space: pre` ASCII blocks DOWN to fit the available
// width — never up. A uniform transform keeps the art perfectly aligned and
// keeps it LIVE: real, themed, selectable terminal text (no raster / SVG).
//
//   • Desktop / wide columns: the art already fits → scale 1 → fully untouched.
//   • Narrow viewports (mobile): the block shrinks just enough to fit, so it no
//     longer overflows or clips, and every glyph column stays aligned.
//
// Scope: operates on the element itself when it IS a <pre>, otherwise on EVERY
// descendant <pre>. So a message body needs the controller only on its wrapper —
// it fits any embedded art and is a no-op when the body holds none (e.g. a list
// table). The wrapper's content-box width is the "available" width each <pre> is
// fit against.
//
// Values:
//   origin: "left" (default) | "center" — the transform anchor. "center" keeps a
//           horizontally-centered block (the start-screen logo) centered as it
//           shrinks; "left" suits left-aligned in-message art.
export default class extends Controller {
  static values = { origin: { type: String, default: "left" } }

  connect() {
    this.fitAll = this.fitAll.bind(this)
    this.fitAll()

    // Re-fit when the available width changes (rotation, resize, sidebar toggle).
    if (typeof ResizeObserver !== "undefined") {
      this.observer = new ResizeObserver(this.fitAll)
      this.observer.observe(this.element)
    }
    // Monospace metrics shift once web fonts swap in — re-measure then.
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(this.fitAll)
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  // Every <pre> this controller is responsible for.
  blocks() {
    return this.element.matches("pre")
      ? [ this.element ]
      : Array.from(this.element.querySelectorAll("pre"))
  }

  fitAll() {
    const available = this.element.clientWidth
    if (!available) return
    this.blocks().forEach((pre) => this.fit(pre, available))
  }

  fit(pre, available) {
    // Reset to natural metrics first so a widen (mobile → desktop) restores 1:1.
    pre.style.transform = ""
    pre.style.transformOrigin = ""
    pre.style.marginBottom = ""

    const natural = pre.scrollWidth
    if (!natural) return

    const scale = Math.min(1, available / natural)
    if (scale === 1) return // fits as-is → leave fully untouched

    pre.style.transformOrigin = this.originValue === "center" ? "top center" : "top left"
    pre.style.transform = `scale(${scale})`
    // A transform doesn't shrink the layout box, so a scaled-down block leaves a
    // gap beneath it. Pull following content up by exactly the height we shed.
    pre.style.marginBottom = `${-pre.offsetHeight * (1 - scale)}px`
  }
}
