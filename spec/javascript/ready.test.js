// spec/javascript/ready.test.js
//
// Tests for pito/ready.js
//
// Invariants:
//   1. window.__pitoReady starts as falsy (undefined).
//   2. The first "turbo:load" event sets it to true.
//   3. A second "turbo:load" does NOT re-run the handler (once: true).

import { describe, it, expect, beforeEach, vi } from "vitest"

// ready.js is a side-effect module (registers a listener on import).
// Reset modules before each test so the listener is re-registered fresh.
describe("pito/ready", () => {
  beforeEach(async () => {
    // Reset __pitoReady and reload the module.
    delete window.__pitoReady
    vi.resetModules()
    await import("pito/ready")
  })

  it("window.__pitoReady is falsy before any turbo:load fires", () => {
    expect(window.__pitoReady).toBeFalsy()
  })

  it("sets window.__pitoReady to true after the first turbo:load", () => {
    document.dispatchEvent(new Event("turbo:load"))
    expect(window.__pitoReady).toBe(true)
  })

  it("remains true after a second turbo:load (once: true listener)", () => {
    document.dispatchEvent(new Event("turbo:load"))
    // Manually reset to verify it does NOT get re-set by the same listener
    // (the listener was already removed after firing once).
    window.__pitoReady = false
    document.dispatchEvent(new Event("turbo:load"))
    // The listener is gone — __pitoReady stays false (we set it manually).
    expect(window.__pitoReady).toBe(false)
  })
})
