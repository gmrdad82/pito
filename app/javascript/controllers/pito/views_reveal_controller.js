// pito--views-reveal
//
// The VIEWS metric's reveal animation — variant "D". EXTENDS the base
// metric-reveal engine with its own choreography: after a short lead-in, the
// braille rows wipe in BOTTOM→UP, one at a time. Each row's reveal is a
// left→right clip wipe with a STRONG trailing cyan glow that fades as it sweeps
// (both ride CSS transitions on `.on`; see `.pito-metric.is-revealing
// .pito-metric__row` in application.css). Inherits the fail-open lifecycle +
// timer primitives from MetricRevealController; only `animate()` differs.
//
// There are NO axes (locked spec) — the reveal goes straight to the braille.
//
// Auto-registered via eagerLoadControllersFrom.

import MetricRevealController from "controllers/pito/metric_reveal_controller"

const LEAD_IN = 300 // ms before the first row (no axis phase)
const CADENCE = 130 // ms between successive rows

export default class extends MetricRevealController {
  async animate() {
    this.revealRows({ leadIn: LEAD_IN, cadence: CADENCE })
  }
}
