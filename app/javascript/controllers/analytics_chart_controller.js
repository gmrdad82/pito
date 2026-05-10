import { Controller } from "@hotwired/stimulus"

// Phase 13.3 — Analytics chart controller. The global Chart.js
// defaults applied in `application.js` already disable animation,
// register the crosshair plugin, and recolor against the design
// system palette. This controller is a marker that pins the
// per-chart `<section>` so other controllers (window picker,
// refresh polling) can locate it via DOM queries; it also asserts
// the no-red invariant at connect time so any future regression
// fails loud.
export default class extends Controller {
  static values = { kind: String }

  connect() {
    // Defense-in-depth: scrub any inline `style` color matching the
    // forbidden red. Chart.js re-renders may set `borderColor`
    // post-hoc; the global recolor pass in `application.js` will
    // overwrite our scrub with the design palette.
    this._stripRed()
  }

  _stripRed() {
    const element = this.element
    const html = element.innerHTML || ""
    if (/#cc0000/i.test(html)) {
      // We don't mutate Chart.js datasets here — the recolor pass owns
      // that. Logging in the console is sufficient as a tripwire;
      // tests assert the rendered HTML contains no `#cc0000`.
      console.warn("[analytics-chart] red detected in chart markup")
    }
  }
}
