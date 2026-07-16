// spec/javascript/fx_fps_controller.test.js
//
// Vitest suite for pito--fx-fps Stimulus controller.
//
// The controller samples requestAnimationFrame cadence over 500ms windows and
// writes `${fps} fps` (or `${fps} fps · fx ${engineFps}` when a fresh
// `pito:fx:fps` window event arrived within the last second) to
// `this.element.textContent`. It is visibility-gated: an IntersectionObserver
// on `this.element` drives private #start()/#stop() from `isIntersecting`, so
// an untoggled chip costs zero rAF work. jsdom has no IntersectionObserver, so
// when it is genuinely undefined the controller falls back to sampling
// unconditionally on connect.
//
// #start()/#stop() are true `#`-private — they cannot be called from outside,
// so every test drives them indirectly: through a fake IntersectionObserver's
// captured callback (visible/hidden), or through the no-IO fallback path.
// requestAnimationFrame/cancelAnimationFrame are stubbed to capture rather
// than auto-run callbacks, so sample windows are advanced deterministically by
// invoking the captured tick callback with a fabricated `now` timestamp.
// performance.now() is stubbed too, since #start()/#stop() reset the window
// off it directly (not off the rAF-supplied `now`).
//
// Covers:
//   1. Hidden at connect (observer fires isIntersecting:false, or never
//      fires) — no rAF is ever scheduled.
//   2. Observer fires visible — rAF is scheduled; driving ticks past a 500ms
//      window writes an `N fps` readout.
//   3. Observer fires visible twice in a row — only one loop (re-entrancy
//      guard): rAF scheduled exactly once before any tick runs.
//   4. Visible then hidden — cancelAnimationFrame is called, and a tick that
//      was already queued before the cancel still bails (`!_running`) without
//      rescheduling or writing.
//   5. Counter freshness — visible → a window closes → hidden → time passes →
//      visible again: the first new window's fps math uses the reset
//      `_windowStart`, not the hidden gap.
//   6. No IntersectionObserver at all (the real jsdom default) — connect()
//      starts sampling unconditionally.
//   7. A `pito:fx:fps` window event received while visible makes the next
//      window render the `· fx N` suffix; a stale one (>1s old) does not.
//   8. disconnect() cancels the loop and removes the engine-event listener —
//      dispatching `pito:fx:fps` afterward doesn't throw or mutate.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import FxFpsController from "controllers/pito/fx_fps_controller"

// ── Fakes / helpers ──────────────────────────────────────────────────────────

// jsdom has no IntersectionObserver — capture instances so tests can fire
// them (mirrors spec/javascript/list_pager_controller.test.js's FakeIO).
let observers
class FakeIO {
  constructor(cb) {
    this.cb = cb
    this.els = []
    observers.push(this)
  }
  observe(el) {
    this.els.push(el)
  }
  disconnect() {
    this.els = []
  }
  trigger(isIntersecting = true) {
    this.cb(this.els.map((target) => ({ isIntersecting, target })))
  }
}

// requestAnimationFrame/cancelAnimationFrame stubs that CAPTURE callbacks
// instead of auto-running them, so sample windows advance only when a test
// explicitly invokes the captured callback with a chosen `now`.
function stubRaf() {
  let nextId = 0
  const calls = [] // { id, cb }
  const rafSpy = vi.fn((cb) => {
    const id = ++nextId
    calls.push({ id, cb })
    return id
  })
  const cafSpy = vi.fn()
  vi.stubGlobal("requestAnimationFrame", rafSpy)
  vi.stubGlobal("cancelAnimationFrame", cafSpy)
  return { rafSpy, cafSpy, calls, latest: () => calls[calls.length - 1] }
}

// performance.now() stub with a settable value — #start()/#stop() read it
// directly to seed/reset `_windowStart`, independent of the `now` a test
// passes into a captured rAF callback.
function stubNow(initial = 0) {
  let value = initial
  vi.spyOn(performance, "now").mockImplementation(() => value)
  return (v) => {
    value = v
  }
}

function buildScaffold() {
  const el = document.createElement("span")
  el.id = "pito-fx-fps"
  el.setAttribute("data-controller", "pito--fx-fps")
  document.body.appendChild(el)
  return el
}

function tick(ms = 20) {
  return new Promise((r) => setTimeout(r, ms))
}

function fxEvent(fps) {
  return new CustomEvent("pito:fx:fps", { detail: { fps } })
}

// ── Suite: IntersectionObserver present (visibility-gated path) ────────────

describe("pito--fx-fps controller (IntersectionObserver present)", () => {
  let app
  let raf
  let setNow

  beforeEach(() => {
    observers = []
    vi.stubGlobal("IntersectionObserver", FakeIO)
    raf = stubRaf()
    setNow = stubNow(0)
    app = Application.start()
    app.register("pito--fx-fps", FxFpsController)
  })

  afterEach(async () => {
    document.body.innerHTML = ""
    await tick(0)
    await app.stop()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it("schedules no rAF at all while hidden at connect (observer fires false)", async () => {
    buildScaffold()
    await tick()

    observers[0].trigger(false)

    expect(raf.rafSpy).not.toHaveBeenCalled()
  })

  it("schedules no rAF at all while hidden at connect (observer never fires)", async () => {
    buildScaffold()
    await tick()

    expect(raf.rafSpy).not.toHaveBeenCalled()
  })

  it("starts sampling when the observer fires visible, writing fps after a 500ms window", async () => {
    const el = buildScaffold()
    await tick()

    // Baseline far past 1000ms: `_engineSeenAt` defaults to 0, so any `now`
    // within 1000ms of that reads as trivially "fresh" (engineFps still
    // null → a spurious "· fx null" suffix) even though no engine event
    // ever fired. Seeding a large baseline keeps this test's assertions
    // about the plain rAF readout uncontaminated by that quirk.
    setNow(100000)
    observers[0].trigger(true)
    expect(raf.rafSpy).toHaveBeenCalledTimes(1)

    // First frame at +100ms: window not yet closed (elapsed 100 < 500).
    raf.latest().cb(100100)
    expect(el.textContent).toBe("")

    // Second frame at +600ms: window closes (elapsed 600 >= 500), 2 frames
    // counted across the two ticks → round(2 * 1000 / 600) = 3.
    raf.latest().cb(100600)
    expect(el.textContent).toBe("3 fps")
  })

  it("only starts one loop when the observer fires visible twice in a row", async () => {
    buildScaffold()
    await tick()

    observers[0].trigger(true)
    observers[0].trigger(true)

    expect(raf.rafSpy).toHaveBeenCalledTimes(1)
  })

  it("cancels the loop when visible flips to hidden, and a queued tick bails without rescheduling", async () => {
    buildScaffold()
    await tick()

    observers[0].trigger(true)
    expect(raf.rafSpy).toHaveBeenCalledTimes(1)
    const queued = raf.latest()

    observers[0].trigger(false)
    expect(raf.cafSpy).toHaveBeenCalledTimes(1)
    expect(raf.cafSpy).toHaveBeenCalledWith(queued.id)

    // Simulate the frame that was already queued before cancellation still
    // firing (browsers offer no hard guarantee) — the internal `!_running`
    // guard must bail without rescheduling or writing.
    expect(() => queued.cb(999)).not.toThrow()
    expect(raf.rafSpy).toHaveBeenCalledTimes(1)
  })

  it("resets the counter on re-visibility so the next window ignores the hidden gap", async () => {
    const el = buildScaffold()
    await tick()

    // Baseline far past 1000ms — see the comment in the previous test: with
    // `_engineSeenAt` defaulting to 0, small absolute `now` values would
    // spuriously read as a "fresh" (but nonexistent) engine event.
    setNow(100000)
    observers[0].trigger(true)
    const first = raf.latest()

    // Close the first window: 1 frame over 500ms → round(1 * 1000 / 500) = 2.
    first.cb(100500)
    expect(el.textContent).toBe("2 fps")

    observers[0].trigger(false)
    expect(raf.cafSpy).toHaveBeenCalledTimes(1)

    // A large hidden gap passes before the chip is revealed again.
    setNow(200000)
    observers[0].trigger(true)
    const second = raf.latest()

    // First tick after re-reveal: elapsed only 100ms — window must not close
    // yet (proves _windowStart was reset to 200000, not left at 100500).
    second.cb(200100)
    expect(el.textContent).toBe("2 fps")

    // Second tick closes the window: 2 frames over 600ms (200600 - 200000) →
    // round(2 * 1000 / 600) = 3. Had the reset not happened, elapsed would
    // have been computed against the stale windowStart (100500) instead,
    // producing a wildly different (near-zero) fps.
    raf.latest().cb(200600)
    expect(el.textContent).toBe("3 fps")
  })

  it("renders the fx suffix only while the engine event is fresh (< 1s old)", async () => {
    const el = buildScaffold()
    await tick()

    setNow(0)
    observers[0].trigger(true)
    const loopA = raf.latest()

    setNow(0)
    window.dispatchEvent(fxEvent(42))

    // Window closes at now=500; engine event seen at 0 → 500ms old, fresh.
    loopA.cb(500)
    expect(el.textContent).toBe("2 fps · fx 42")
  })

  it("does not render the fx suffix once the engine event is stale (>= 1s old)", async () => {
    const el = buildScaffold()
    await tick()

    setNow(0)
    observers[0].trigger(true)
    const loop = raf.latest()

    setNow(0)
    window.dispatchEvent(fxEvent(42))

    // Window closes at now=1500; engine event seen at 0 → 1500ms old, stale.
    loop.cb(1500)
    expect(el.textContent).toBe("1 fps")
  })

  it("disconnect cancels the loop and removes the engine listener (no throw, no mutation after)", async () => {
    const el = buildScaffold()
    await tick()

    observers[0].trigger(true)
    expect(raf.rafSpy).toHaveBeenCalledTimes(1)

    document.body.removeChild(el)
    await tick()

    expect(raf.cafSpy).toHaveBeenCalledTimes(1)

    const before = el.textContent
    expect(() => window.dispatchEvent(fxEvent(99))).not.toThrow()
    expect(el.textContent).toBe(before)
  })
})

// ── Suite: no IntersectionObserver (genuine jsdom default) ─────────────────

describe("pito--fx-fps controller (no IntersectionObserver — jsdom fallback)", () => {
  let app
  let raf

  beforeEach(() => {
    // Deliberately do NOT stub IntersectionObserver — jsdom has none by
    // default, which is exactly the fallback path this suite verifies.
    expect(typeof IntersectionObserver).toBe("undefined")
    raf = stubRaf()
    app = Application.start()
    app.register("pito--fx-fps", FxFpsController)
  })

  afterEach(async () => {
    document.body.innerHTML = ""
    await tick(0)
    await app.stop()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it("starts sampling unconditionally on connect", async () => {
    buildScaffold()
    await tick()

    expect(raf.rafSpy).toHaveBeenCalledTimes(1)
  })
})
