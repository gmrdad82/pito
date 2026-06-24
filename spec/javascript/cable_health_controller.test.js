// spec/javascript/cable_health_controller.test.js
//
// Vitest (jsdom) suite for the pito--cable-health Stimulus controller.
//
// The controller's only job now: when the tab returns visible after being
// hidden longer than HIDDEN_RELOAD_MS, reload to re-establish a possibly-dropped
// cable and backfill from the DB. There is NO HTTP health poll and NO offline
// flag anymore — the old `/up` ping 404'd after 0.7.0 removed that route, which
// falsely flagged the cable offline ~60s in and made the chatbox eat messages.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import CableHealthController from "controllers/pito/cable_health_controller"

const HIDDEN_RELOAD_MS = 30000

async function buildApp() {
  const el = document.createElement("div")
  el.setAttribute("data-controller", "pito--cable-health")
  document.body.appendChild(el)

  const app = Application.start()
  app.register("pito--cable-health", CableHealthController)
  await Promise.resolve() // let Stimulus connect
  return { app }
}

async function teardownApp(app) {
  document.body.innerHTML = ""
  await Promise.resolve() // let Stimulus's MutationObserver fire disconnect()
  app.stop()
}

function setVisibility(state) {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => state,
  })
  document.dispatchEvent(new Event("visibilitychange"))
}

describe("pito--cable-health controller", () => {
  let originalLocation

  beforeEach(() => {
    originalLocation = window.location
    delete window.location
    window.location = { reload: vi.fn() }
    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      get: () => "visible",
    })
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    window.location = originalLocation
    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      get: () => "visible",
    })
    document.body.innerHTML = ""
  })

  it("connects without flagging the body offline (no poll, no offline state)", async () => {
    const { app } = await buildApp()
    expect(document.body.hasAttribute("data-pito-cable-offline")).toBe(false)
    await teardownApp(app)
  })

  it("never pings the network — there is no /up health poll", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    const { app } = await buildApp()
    await Promise.resolve()
    expect(fetchSpy).not.toHaveBeenCalled()
    await teardownApp(app)
  })

  it("does NOT reload if the tab was hidden for less than HIDDEN_RELOAD_MS", async () => {
    vi.useFakeTimers()
    const { app } = await buildApp()

    setVisibility("hidden")
    vi.advanceTimersByTime(15000) // < 30s
    setVisibility("visible")

    expect(window.location.reload).not.toHaveBeenCalled()
    await teardownApp(app)
  })

  it("reloads when the tab was hidden longer than HIDDEN_RELOAD_MS", async () => {
    vi.useFakeTimers()
    const { app } = await buildApp()

    setVisibility("hidden")
    vi.advanceTimersByTime(HIDDEN_RELOAD_MS + 1000) // > 30s
    setVisibility("visible")

    expect(window.location.reload).toHaveBeenCalled()
    await teardownApp(app)
  })
})
