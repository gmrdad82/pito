// spec/javascript/scrollback_controller.test.js
//
// Tests for pito--scrollback Stimulus controller (scrollback_controller.js).
//
// Strategy: mount the real controller on a jsdom div, then trigger events and
// DOM mutations and assert scrollTo behaviour via a counter function.
//
// jsdom layout limitations:
//   - scrollHeight, scrollTop, clientHeight are always 0 — must be overridden
//     via Object.defineProperty for each test that cares about scroll position.
//   - scrollTo does not exist on jsdom elements — stubbed on the prototype.
//   - Stimulus needs a real ~10ms delay to connect in jsdom (not just setTimeout 0).
//     MutationObserver callbacks in jsdom are also asynchronous and require a real
//     wait — tests use `waitForConnect()` (10ms) and `waitForMO()` (50ms).
//   - requestAnimationFrame in jsdom runs synchronously in the same tick after the
//     MutationObserver callback, so no extra wait is needed for the rAF re-scroll.
//   - Smooth-scroll animation timing (SMOOTH_SCROLL_GRACE 600 ms flag) cannot
//     be simulated in jsdom. The programmaticScrolling flag is set to false after
//     the connect-time grace timer (setTimeout 0) fires.
//
// Behaviours verified:
//   1. pito:submitted calls scrollTo (unlocks + scrolls to bottom)
//   2. A new appended child triggers scrollTo via MutationObserver
//   3. Appended echo/non-echo nodes dispatch pito:echo-appended / pito:result-appended
//   4. User scroll-up > 80 px locks auto-scroll (suppresses scrollTo on MO)
//   5. User scroll near bottom (< 80 px) does NOT lock
//   6. Downward scroll after pito:submitted does not set the lock

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ScrollbackController from "controllers/pito/scrollback_controller"

// ── jsdom stubs ───────────────────────────────────────────────────────────────
// jsdom does not implement scrollTo on elements.
if (!Element.prototype.scrollTo) {
  Element.prototype.scrollTo = function () {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Build and connect a scrollback element. Returns { el, scrollCalls }.
// scrollCalls is an array that captures each scrollTo call's argument.
function buildScrollback(layoutOpts = {}) {
  const el = document.createElement("div")
  el.id = "pito-scrollback"
  el.setAttribute("data-controller", "pito--scrollback")
  document.body.appendChild(el)

  const { scrollHeight = 500, clientHeight = 300, scrollTop = 0 } = layoutOpts
  let _scrollTop = scrollTop
  Object.defineProperty(el, "scrollHeight", { get: () => scrollHeight, configurable: true })
  Object.defineProperty(el, "clientHeight", { get: () => clientHeight, configurable: true })
  Object.defineProperty(el, "scrollTop", {
    get: () => _scrollTop,
    set: (v) => { _scrollTop = v },
    configurable: true,
  })

  const scrollCalls = []
  el.scrollTo = (opts) => scrollCalls.push(opts)

  return { el, scrollCalls }
}

// Wait for Stimulus to connect (10ms is enough in jsdom).
function waitForConnect() {
  return new Promise((r) => setTimeout(r, 10))
}

// Wait for MutationObserver callbacks to flush (jsdom dispatches them asynchronously).
function waitForMO() {
  return new Promise((r) => setTimeout(r, 50))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--scrollback controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--scrollback", ScrollbackController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  // ── pito:submitted ────────────────────────────────────────────────────────

  it("pito:submitted calls scrollTo on the scrollback element", async () => {
    const { el, scrollCalls } = buildScrollback()
    await waitForConnect()

    const before = scrollCalls.length
    document.dispatchEvent(new CustomEvent("pito:submitted"))

    expect(scrollCalls.length).toBeGreaterThan(before)
    expect(scrollCalls.at(-1)).toMatchObject({ top: expect.any(Number) })
  })

  it("pito:submitted unlocks scroll after a manual scroll-up lock", async () => {
    const { el, scrollCalls } = buildScrollback({ scrollHeight: 500, scrollTop: 200, clientHeight: 300 })
    await waitForConnect()

    // Lock: first scroll to initialise lastScrollTop, then scroll up.
    el.dispatchEvent(new Event("scroll"))
    el.scrollTop = 50
    el.dispatchEvent(new Event("scroll"))

    // Submit: should unlock and re-scroll.
    const before = scrollCalls.length
    document.dispatchEvent(new CustomEvent("pito:submitted"))

    expect(scrollCalls.length).toBeGreaterThan(before)
  })

  // ── MutationObserver triggers scroll ─────────────────────────────────────

  it("appending a child triggers scrollTo via MutationObserver", async () => {
    const { el, scrollCalls } = buildScrollback()
    await waitForConnect()

    const before = scrollCalls.length
    el.appendChild(document.createElement("div"))
    await waitForMO()

    expect(scrollCalls.length).toBeGreaterThan(before)
  })

  it("appended echo element (data-accent=purple) dispatches pito:echo-appended", async () => {
    const { el } = buildScrollback()
    await waitForConnect()

    let echoCaught = null
    document.addEventListener("pito:echo-appended", (e) => { echoCaught = e }, { once: true })

    const wrapper = document.createElement("div")
    const inner = document.createElement("div")
    inner.dataset.accent = "purple"
    wrapper.appendChild(inner)
    el.appendChild(wrapper)
    await waitForMO()

    expect(echoCaught).not.toBeNull()
  })

  it("appended non-echo element dispatches pito:result-appended", async () => {
    const { el } = buildScrollback()
    await waitForConnect()

    let resultCaught = null
    document.addEventListener("pito:result-appended", (e) => { resultCaught = e }, { once: true })

    el.appendChild(document.createElement("div"))
    await waitForMO()

    expect(resultCaught).not.toBeNull()
  })

  // ── User scroll-up locking ────────────────────────────────────────────────

  it("scroll-up > SCROLL_LOCK_THRESHOLD (80 px) suppresses auto-scroll", async () => {
    // scrollHeight=500, clientHeight=300 → bottom = scrollTop 200
    // After scroll-up to 50: distanceFromBottom = 500 - 50 - 300 = 150 > 80 → lock
    const { el, scrollCalls } = buildScrollback({ scrollHeight: 500, scrollTop: 200, clientHeight: 300 })
    await waitForConnect()

    // Fire a scroll event to initialise lastScrollTop, then scroll up.
    el.dispatchEvent(new Event("scroll"))
    el.scrollTop = 50
    el.dispatchEvent(new Event("scroll"))

    // Now a child appends — scrollTo should NOT be called (locked).
    const before = scrollCalls.length
    el.appendChild(document.createElement("div"))
    await waitForMO()

    expect(scrollCalls.length).toBe(before)
  })

  it("scroll-up within SCROLL_LOCK_THRESHOLD (<= 80 px) does not lock", async () => {
    // After scroll: distanceFromBottom = 500 - 195 - 300 = 5 < 80 → no lock
    const { el, scrollCalls } = buildScrollback({ scrollHeight: 500, scrollTop: 200, clientHeight: 300 })
    await waitForConnect()

    // Fire a scroll event to initialise lastScrollTop, then scroll up slightly.
    el.dispatchEvent(new Event("scroll"))
    el.scrollTop = 195
    el.dispatchEvent(new Event("scroll"))

    const before = scrollCalls.length
    el.appendChild(document.createElement("div"))
    await waitForMO()

    expect(scrollCalls.length).toBeGreaterThan(before)
  })

  // ── Programmatic-scroll flag prevents false lock ──────────────────────────
  //
  // JSDOM NOTE: The smooth-scroll animation (SMOOTH_SCROLL_GRACE 600 ms) cannot
  // be simulated in jsdom. We test the observable result: a programmatic
  // pito:submitted followed immediately by a downward scroll event does not set
  // the lock, so a subsequent append still triggers scrollTo.

  it("downward scroll after pito:submitted does not set the lock", async () => {
    const { el, scrollCalls } = buildScrollback({ scrollHeight: 500, scrollTop: 200, clientHeight: 300 })
    await waitForConnect()

    // Trigger a programmatic scroll via pito:submitted.
    document.dispatchEvent(new CustomEvent("pito:submitted"))

    // Fire a downward scroll event immediately.
    el.scrollTop = 210
    el.dispatchEvent(new Event("scroll"))

    const before = scrollCalls.length
    el.appendChild(document.createElement("div"))
    await waitForMO()

    // Downward event during programmatic scroll should not lock.
    expect(scrollCalls.length).toBeGreaterThan(before)
  })
})
