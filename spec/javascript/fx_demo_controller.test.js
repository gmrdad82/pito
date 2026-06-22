// spec/javascript/fx_demo_controller.test.js
//
// Tests for the pito--fx-demo controller (fx_demo_controller.js): the LOOPING
// showcase used by `/config fx --help`. Each row re-runs ONE named effect on its
// own element forever (reusing the shared reveal engine), and renders STATIC when
// motion is suppressed.
//
// Tests use a SHORT interval value (the controller defaults to ~2s in
// production) so the loop can be observed quickly and deterministically.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import FxDemoController from "controllers/pito/fx_demo_controller"
import { RevealEngine } from "pito/reveal_engine"

const INTERVAL = 40 // ms between demo cycles in tests

// Build an fx-demo showcase row: a controller div carrying the effect value and a
// single text span (mirrors config.rb's fx_showcase_row).
function buildRow(effect, text = "watch this effect demo") {
  const div = document.createElement("div")
  div.setAttribute("data-controller", "pito--fx-demo")
  div.setAttribute("data-pito--fx-demo-effect-value", effect)
  div.setAttribute("data-pito--fx-demo-interval-ms-value", String(INTERVAL))

  const span = document.createElement("span")
  span.className = "text-fg-dim"
  span.textContent = text
  div.appendChild(span)

  document.body.appendChild(div)
  return { div, span }
}

describe("pito--fx-demo controller", () => {
  let app

  beforeEach(() => {
    // jsdom has no matchMedia; motionDisabled() calls it. Default: motion enabled.
    window.matchMedia = () => ({ matches: false })
    app = Application.start()
    app.register("pito--fx-demo", FxDemoController)
  })

  afterEach(async () => {
    document.body.innerHTML = "" // disconnect controllers (stop loops) BEFORE stopping the app
    await app.stop()
    vi.restoreAllMocks()
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // Poll until a condition holds (or timeout). Wall-clock generous, so loop
  // assertions don't flake under CPU load / concurrent runs (real-timer based).
  async function waitUntil(predicate, timeout = 4000, step = 10) {
    const start = Date.now()
    while (!predicate()) {
      if (Date.now() - start > timeout) return
      await new Promise((r) => setTimeout(r, step))
    }
  }

  it("runs the effect once on connect (the first demo cycle)", async () => {
    const runSpy = vi.spyOn(RevealEngine.prototype, "run")
    buildRow("typewriter")
    await waitForConnect()

    expect(runSpy).toHaveBeenCalledTimes(1)
    expect(runSpy).toHaveBeenCalledWith("typewriter")
  })

  it("LOOPS — re-runs the effect after the interval", async () => {
    const runSpy = vi.spyOn(RevealEngine.prototype, "run")
    buildRow("typewriter", "loop me")
    await waitForConnect()
    expect(runSpy).toHaveBeenCalledTimes(1)

    // The loop must re-run (each cycle: a short reveal + the INTERVAL pause).
    await waitUntil(() => runSpy.mock.calls.length >= 2)

    expect(runSpy.mock.calls.length).toBeGreaterThanOrEqual(2) // looped at least once more
    expect(runSpy).toHaveBeenCalledWith("typewriter")          // every cycle re-runs the same effect
  })

  it("re-PRIMES each cycle (the loop resets the initial frame every time)", async () => {
    const primeSpy = vi.spyOn(RevealEngine.prototype, "prime")
    buildRow("typewriter", "primed text")
    await waitForConnect()

    expect(primeSpy).toHaveBeenCalledTimes(1) // first cycle primed

    // Each loop builds a fresh engine and primes it again — so prime is called
    // once per cycle, proving the initial frame is reset on every loop.
    await waitUntil(() => primeSpy.mock.calls.length >= 2)
    expect(primeSpy.mock.calls.length).toBeGreaterThanOrEqual(2)
    expect(primeSpy).toHaveBeenCalledWith("typewriter")
  })

  it("renders STATIC (never runs) under prefers-reduced-motion", async () => {
    window.matchMedia = () => ({ matches: true }) // reduced motion
    const runSpy = vi.spyOn(RevealEngine.prototype, "run")
    const { span } = buildRow("scramble", "stays put")
    await waitForConnect()
    await new Promise((r) => setTimeout(r, 200))

    expect(runSpy).not.toHaveBeenCalled()
    expect(span.textContent).toBe("stays put") // full text untouched
  })

  it("renders STATIC (never runs) when fx/motion is off via #pito-settings", async () => {
    const settings = document.createElement("div")
    settings.id = "pito-settings"
    settings.dataset.fx = "false" // /config motion off
    document.body.appendChild(settings)

    const runSpy = vi.spyOn(RevealEngine.prototype, "run")
    const { span } = buildRow("comet", "no sweep here")
    await waitForConnect()
    await new Promise((r) => setTimeout(r, 200))

    expect(runSpy).not.toHaveBeenCalled()
    expect(span.textContent).toBe("no sweep here")
    expect(span.style.opacity).not.toBe("0.01") // never dimmed
  })

  it("stops looping on disconnect (no further cycles after teardown)", async () => {
    const runSpy = vi.spyOn(RevealEngine.prototype, "run")
    const { div } = buildRow("typewriter", "bye")
    await waitForConnect()

    // Remove the element → Stimulus disconnect → loop stops.
    div.remove()
    await waitForConnect()
    const countAtDisconnect = runSpy.mock.calls.length

    // Well past several intervals: no new cycle should have started.
    await new Promise((r) => setTimeout(r, 500))
    expect(runSpy.mock.calls.length).toBe(countAtDisconnect)
  })
})
