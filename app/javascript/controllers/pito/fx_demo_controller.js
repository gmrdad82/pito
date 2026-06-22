// Pito::FxDemoController
//
// A LOOPING showcase of ONE reveal effect, used by the `/config fx --help`
// man page so the owner can watch what each effect (typewriter / scramble /
// comet) actually does. Each showcase row mounts this controller with its own
// `effect` value and loops that effect on its own element forever.
//
// It reuses the shared `pito/reveal_engine` RevealEngine — the SAME decomposition
// + per-effect runners the live `pito--typewriter` controller uses — so the demo
// is a faithful preview of the real reveal, not a re-implementation. Each loop
// iteration builds a fresh engine on this element's subtree, primes the effect's
// initial frame, runs it to completion, then (after a short pause) repeats.
//
// fx / motion gated: when motion is off (`/config motion off`) or the user
// prefers reduced motion, the row renders STATIC — no loop runs, the
// server-rendered full text simply stays in place.

import { Controller } from "@hotwired/stimulus"
import { motionDisabled } from "pito/settings"
import { RevealEngine } from "pito/reveal_engine"

// Pause between one demo finishing and the next starting (the "every ~2s"
// cadence). Overridable per-element (kept small in tests) but defaulted here.
const DEMO_INTERVAL_MS = 2000

export default class extends Controller {
  static values = { effect: String, intervalMs: Number }

  connect() {
    // Static when motion is suppressed — never loop, leave the full text in place.
    if (motionDisabled()) return

    this._stopped = false
    this.#runOnce()
  }

  disconnect() {
    this._stopped = true
    clearTimeout(this._timer)
    this._engine?.cancel()
  }

  // ── private ────────────────────────────────────────────────────────────────

  // One demo cycle: fresh engine → prime → run → schedule the next cycle.
  #runOnce() {
    // Bail if stopped or the row has been detached (a removed showcase must never
    // keep looping, even if its disconnect hasn't fired yet).
    if (this._stopped || !this.element.isConnected) return

    const engine = new RevealEngine([this.element])
    this._engine = engine

    if (engine.collect().length === 0) return

    const effect = this.effectValue || "typewriter"
    engine.prime(effect)

    engine.run(effect).then(() => {
      if (this._stopped) return
      this._timer = setTimeout(() => this.#runOnce(), this.intervalMsValue || DEMO_INTERVAL_MS)
    })
  }
}
