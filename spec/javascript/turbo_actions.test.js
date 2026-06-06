// spec/javascript/turbo_actions.test.js
//
// Tests for pito/turbo_actions.js
//
// The module registers a `navigate` Turbo StreamAction on the first
// turbo:load event.  The action sets window.location.href = this.target.
//
// jsdom limitation: window.location.href cannot be set to an arbitrary URL
// in jsdom without triggering navigation errors.  We stub window.location
// and Turbo.StreamActions to test the registration logic in isolation.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// ── Setup ─────────────────────────────────────────────────────────────────────

describe("pito/turbo_actions", () => {
  let streamActionsSpy
  let navigateAction

  beforeEach(async () => {
    // Stub Turbo global with a StreamActions object we can inspect.
    streamActionsSpy = {}
    globalThis.Turbo = { StreamActions: streamActionsSpy }

    // Reset modules and import fresh so the turbo:load listener re-registers.
    vi.resetModules()
    await import("pito/turbo_actions")
  })

  afterEach(() => {
    delete globalThis.Turbo
    vi.restoreAllMocks()
  })

  it("registers the navigate action after turbo:load fires", () => {
    // Fire turbo:load to trigger the registration.
    window.dispatchEvent(new Event("turbo:load"))
    expect(typeof streamActionsSpy.navigate).toBe("function")
  })

  it("does NOT register the action before turbo:load fires", () => {
    // The listener is registered on turbo:load — before it fires, the action
    // should not yet exist.
    expect(streamActionsSpy.navigate).toBeUndefined()
  })

  it("navigate action sets window.location.href to this.target", () => {
    window.dispatchEvent(new Event("turbo:load"))

    // Call the action with a mock context where `this.target` is a URL.
    const mockContext = { target: "/auth/google_oauth2" }
    const hrefSetter = vi.fn()
    Object.defineProperty(window, "location", {
      value: { ...window.location, set href(v) { hrefSetter(v) } },
      configurable: true,
    })

    streamActionsSpy.navigate.call(mockContext)
    expect(hrefSetter).toHaveBeenCalledWith("/auth/google_oauth2")
  })

  it("removes the turbo:load listener after the first fire (once pattern)", () => {
    window.dispatchEvent(new Event("turbo:load"))
    const registered = streamActionsSpy.navigate

    // Reset StreamActions and fire again — action should NOT re-register.
    delete streamActionsSpy.navigate
    window.dispatchEvent(new Event("turbo:load"))

    // The second fire should not have put navigate back (listener removed).
    expect(streamActionsSpy.navigate).toBeUndefined()
  })
})
