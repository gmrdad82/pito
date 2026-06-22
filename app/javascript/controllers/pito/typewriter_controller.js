// Pito::TypewriterController
//
// Progressively reveals a segment's content when it arrives live over the cable.
// A thin Stimulus wrapper around the shared `pito/reveal_engine` RevealEngine:
// the engine owns the decomposition + the three per-effect runners (typewriter /
// scramble / comet) + the shared log-scaled duration; this controller owns the
// LIVE concerns — effect resolution, the reveal-queue concurrency slot, the
// skip/motion gate, and the one-shot `doneEvent` completion signal.
//
// Effect resolution (shared contract with the --help showcase):
//     element's own `effect` value  →  global fxEffect()  →  "typewriter".
// A per-element override (data-pito--typewriter-effect-value) wins, so a showcase
// row can force one effect regardless of the global /config setting.
//
// Targets `body` / `prose` / `htmlProse` are the animatable subtrees handed to
// the engine; chrome (accent bar, hints, meta-line) is not a target and renders
// instantly. The always-pop set (bars / avatars / covers / thumbnails) and the
// text/atomic unit model live in the engine.
//
// Conditions that skip animation (instant full-text, every effect):
//   • prefers-reduced-motion matches.
//   • window.__pitoReady is falsy (initial server-rendered page load).
//   • !fxEnabled() — the owner disabled fx (MOTION off) in /config.
//   • There is nothing to reveal (no units).
//   • opts.instant from the reveal scheduler (concurrency backpressure).
//
// Concurrency: reveals are scheduled through reveal_queue.js, which runs each job
// CONCURRENTLY (no FIFO). Backpressure snaps the overflow instant when too many
// reveals animate at once.
//
// Completion signal (doneEvent value): when set, the controller dispatches that
// document event ONCE when its reveal settles — on EVERY path (animated
// completion for any effect, instant/backpressure, cancellation, skip-guard).

import { Controller } from "@hotwired/stimulus"
import { enqueue } from "pito/reveal_queue"
import { fxEnabled, fxEffect } from "pito/settings"
import { RevealEngine } from "pito/reveal_engine"

export default class extends Controller {
  static targets = ["body", "prose", "htmlProse"]
  static values  = { doneEvent: String, effect: String }

  connect() {
    if (this.#skipAnimation()) { this.#signalDone(); return }

    const targets = [
      ...(this.hasBodyTarget ? [this.bodyTarget] : []),
      ...(this.hasProseTarget ? this.proseTargets : []),
      ...(this.hasHtmlProseTarget ? this.htmlProseTargets : [])
    ]

    const engine = new RevealEngine(targets)
    const units  = engine.collect()

    // Nothing animatable (e.g. an always-pop-only card, or an empty echo) — still
    // settle the completion signal so a waiting listener does not hang.
    if (units.length === 0) { this.#signalDone(); return }

    // Guard double-run (e.g. Turbo re-connects same element).
    if (this._connected) return
    this._connected = true
    this._engine = engine

    const effect = this.#resolveEffect()

    // Prime the initial frame synchronously so a box is never an empty/flat shell
    // before its reveal job runs.
    engine.prime(effect)

    enqueue(({ instant } = {}) => {
      if (instant || engine.cancelled) {
        engine.finishInstant()
        return Promise.resolve()
      }
      return engine.run(effect)
    }).then(() => this.#signalDone(), () => this.#signalDone())
  }

  disconnect() {
    // Cancel the in-flight reveal: it restores content/visibility and settles the
    // engine's promise, which frees the reveal-queue slot (a leaked slot would
    // push later messages toward instant-mode backpressure sooner).
    this._engine?.cancel()
    // Skip-guard / no-units mounts never built an engine — still settle the signal.
    this.#signalDone()
  }

  // ── private ────────────────────────────────────────────────────────────────

  // Effect resolution contract: per-element override → global → default.
  #resolveEffect() {
    return this.effectValue || fxEffect() || "typewriter"
  }

  // Dispatch the configured completion event exactly once, when this segment's
  // reveal settles. No-op when no doneEvent value was set.
  #signalDone() {
    if (this._doneSignalled) return
    this._doneSignalled = true
    if (!this.doneEventValue) return
    document.dispatchEvent(new CustomEvent(this.doneEventValue, { bubbles: true }))
  }

  #skipAnimation() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return true
    if (!window.__pitoReady) return true
    if (!fxEnabled()) return true
    return false
  }
}
