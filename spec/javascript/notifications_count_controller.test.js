// spec/javascript/notifications_count_controller.test.js
//
// Tests for pito/notifications_count_controller.js
//
// The controller uses a module-level prevLatestId that persists across Turbo
// Stream replacements (disconnect → reconnect). Each test establishes its own
// baseline (a first connect at a known latest-id), then simulates the next
// broadcast — so tests are order-independent.
//
// The chime fires only when the MAX notification id rises (a genuinely new
// notification). A read/unread TOGGLE changes the unread count but NOT the max
// id, so it must NOT fire — that's the regression this guards.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import NotificationsCountController from "controllers/pito/notifications_count_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

const waitForConnect = () => new Promise((r) => setTimeout(r, 10))

function buildDOM(latestId, count = 0) {
  const span = document.createElement("span")
  span.setAttribute("data-controller", "pito--notifications-count")
  // Double-dash identifiers can't be expressed via dataset camelCase.
  span.setAttribute("data-pito--notifications-count-count-value", String(count))
  span.setAttribute("data-pito--notifications-count-latest-id-value", String(latestId))
  document.body.appendChild(span)
  return span
}

async function connectWith(latestId, count = 0) {
  buildDOM(latestId, count)
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
    await connectWith(1)
    expect(arrivedEvents).toHaveLength(0)
  })

  it("dispatches pito:notification-arrived when the max notification id rises", async () => {
    await connectWith(10)
    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWith(11)

    expect(arrivedEvents).toHaveLength(1)
  })

  it("does NOT dispatch on a read/unread toggle (unread count changes, max id unchanged)", async () => {
    await connectWith(10, 2)        // baseline: max id 10, 2 unread
    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWith(10, 3)        // toggle read→unread: count up, SAME max id

    expect(arrivedEvents).toHaveLength(0)
  })

  it("does NOT dispatch when the max id is unchanged (no-op broadcast)", async () => {
    await connectWith(10)
    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWith(10)

    expect(arrivedEvents).toHaveLength(0)
  })

  it("dispatches on a new id, then NOT on a subsequent toggle", async () => {
    await connectWith(5)
    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWith(7)            // new notification → dispatch
    expect(arrivedEvents).toHaveLength(1)

    arrivedEvents.length = 0

    document.body.innerHTML = ""
    await connectWith(7, 9)         // toggle bumps count, id steady → no dispatch
    expect(arrivedEvents).toHaveLength(0)
  })
})
