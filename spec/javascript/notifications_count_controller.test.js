// spec/javascript/notifications_count_controller.test.js
//
// Tests for pito/notifications_count_controller.js
//
// The controller uses a module-level prevCount that persists across Turbo Stream
// replacements (disconnect → reconnect). Each test drives prevCount into a known
// state via a "baseline" connect, then simulates the replacement.
//
// Timing: Stimulus connects via MutationObserver which is async in jsdom.
// We use waitForConnect (10 ms real-timer pause) after each DOM insertion,
// matching the convention in resume_controller.test.js.
//
// No fake timers needed — the controller dispatches synchronously in connect().

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import NotificationsCountController from "controllers/pito/notifications_count_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

// Wait one tick so Stimulus's MutationObserver fires and connect() runs.
const waitForConnect = () => new Promise((r) => setTimeout(r, 10))

function buildDOM(count) {
  const span = document.createElement("span")
  span.setAttribute("data-controller", "pito--notifications-count")
  // The controller identifier has a double dash (pito--notifications-count).
  // dataset camelCase cannot encode double dashes, so setAttribute is required.
  span.setAttribute("data-pito--notifications-count-count-value", String(count))
  document.body.appendChild(span)
  return span
}

async function connectWithCount(count) {
  buildDOM(count)
  await waitForConnect()
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("NotificationsCountController", () => {
  let app
  let arrivedEvents

  function onArrived() { arrivedEvents.push(1) }

  beforeEach(async () => {
    arrivedEvents = []
    document.addEventListener("pito:notification-arrived", onArrived)

    app = Application.start()
    app.register("pito--notifications-count", NotificationsCountController)
    await waitForConnect()
  })

  afterEach(async () => {
    document.removeEventListener("pito:notification-arrived", onArrived)
    await app.stop()
    document.body.innerHTML = ""
    arrivedEvents = []
  })

  it("does NOT dispatch on the first connect (page-load baseline)", async () => {
    // prevCount may already be set from a prior test; either way, no increase
    // from null→N (guard) or N→N (equal) should fire.
    // We can guarantee no increase by connecting with count 0 the first time
    // after a fresh app — if prevCount was null, guard fires; if it was set
    // to 0 by a prior test, equal → no fire. Then raise: counts as increase.
    // But the requirement is just: the very first DOM insertion never sounds.
    //
    // Strategy: connect with count 1. If prevCount is null → no dispatch (guard).
    // If prevCount was, say, 5 from a prior test → 1 < 5 → no dispatch.
    // In both cases, 0 dispatches expected.
    await connectWithCount(1)
    expect(arrivedEvents).toHaveLength(0)
  })

  it("dispatches pito:notification-arrived when count increases", async () => {
    // Establish baseline (prevCount = 2).
    await connectWithCount(2)
    arrivedEvents.length = 0

    // Simulate Turbo Stream replacement: remove then re-add with higher count.
    document.body.innerHTML = ""
    await connectWithCount(3)

    expect(arrivedEvents).toHaveLength(1)
  })

  it("does NOT dispatch when count decreases (mark-as-read)", async () => {
    await connectWithCount(3)
    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWithCount(2)

    expect(arrivedEvents).toHaveLength(0)
  })

  it("does NOT dispatch when count is equal (no-op broadcast)", async () => {
    await connectWithCount(2)
    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWithCount(2)

    expect(arrivedEvents).toHaveLength(0)
  })

  it("dispatches on increase, then NOT on subsequent decrease", async () => {
    await connectWithCount(1)
    arrivedEvents.length = 0

    // Goes up: dispatch.
    document.body.innerHTML = ""
    await connectWithCount(4)
    expect(arrivedEvents).toHaveLength(1)

    arrivedEvents.length = 0

    // Goes back down: no dispatch.
    document.body.innerHTML = ""
    await connectWithCount(2)
    expect(arrivedEvents).toHaveLength(0)
  })
})
