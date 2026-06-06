// spec/javascript/cable_health_controller.test.js
//
// Vitest (jsdom) suite for pito--cable-health Stimulus controller.
//
// STRATEGY
//   Each test builds its own fresh Stimulus Application so controllers
//   don't share state.  Fake timers are activated inside each test and
//   restored in afterEach.  Fetch is controlled via vi.stubGlobal.
//   window.location is replaced with a plain object carrying a reload spy,
//   then restored in afterEach (jsdom marks .reload non-configurable so
//   vi.spyOn cannot be used directly).
//
// COVERAGE
//   connect() — ping on connect; interval scheduling.
//   Online/offline state machine:
//     1 failure  → no offline mark.
//     2 failures → body[data-pito-cable-offline] set.
//     success after offline → attribute removed + failure counter reset.
//   Visibility reload:
//     hidden < HIDDEN_RELOAD_MS → no reload.
//     hidden ≥ HIDDEN_RELOAD_MS → location.reload() called.
//     offline while tab becomes visible → reload triggered.
//
// SKIPPED (jsdom limitations)
//   - Real WebSocket / ActionCable connectivity (no WS in jsdom).
//   - Actual network fetch behaviour (mocked via vi.stubGlobal).
//   - Exact Date.now() / timer semantics noted inline where jsdom/vitest
//     fake-timer interactions require careful setup.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import CableHealthController from "controllers/pito/cable_health_controller"

// ── Constants mirror the controller ──────────────────────────────────────────

const PING_INTERVAL_MS  = 30000
const OFFLINE_THRESHOLD = 2

// ── Helpers ───────────────────────────────────────────────────────────────────

function okResponse()   { return Promise.resolve({ ok: true }) }
function failResponse() { return Promise.reject(new TypeError("Network error")) }

// Start a fresh Stimulus application with a single cable-health element.
// Returns { app, el }.  Call await teardownApp(app) in the test to clean up.
async function buildApp(fetchImpl = () => okResponse()) {
  vi.stubGlobal("fetch", vi.fn().mockImplementation(fetchImpl))

  const el = document.createElement("div")
  el.setAttribute("data-controller", "pito--cable-health")
  document.body.appendChild(el)

  const app = Application.start()
  app.register("pito--cable-health", CableHealthController)

  // One microtask tick so Stimulus can connect the controller.
  await Promise.resolve()
  return { app, el }
}

async function teardownApp(app) {
  // Clear DOM first so Stimulus's MutationObserver fires and calls disconnect()
  // on all connected controllers (including cleaning up their AbortControllers
  // and visibilitychange listeners). Then stop the app so the observer itself shuts down.
  document.body.innerHTML = ""
  await Promise.resolve()  // allow Stimulus's MO callback to fire
  app.stop()
  document.body.removeAttribute("data-pito-cable-offline")
}

function setVisibility(state) {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => state,
  })
  document.dispatchEvent(new Event("visibilitychange"))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--cable-health controller", () => {
  let originalLocation

  beforeEach(() => {
    // Replace window.location so reload is interceptable in all tests.
    originalLocation = window.location
    delete window.location
    window.location = { reload: vi.fn() }

    // Ensure visibility starts visible.
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
    document.body.removeAttribute("data-pito-cable-offline")
  })

  // ── connect() — immediate first ping ────────────────────────────────────────

  describe("connect() — initial ping", () => {
    it("calls fetch /up immediately on connect", async () => {
      const { app } = await buildApp(okResponse)
      expect(fetch).toHaveBeenCalledWith("/up", expect.objectContaining({ method: "HEAD" }))
      await teardownApp(app)
    })

    it("does not mark body offline after a successful ping", async () => {
      const { app } = await buildApp(okResponse)
      expect(document.body.hasAttribute("data-pito-cable-offline")).toBe(false)
      await teardownApp(app)
    })
  })

  // ── interval scheduling ──────────────────────────────────────────────────────

  describe("ping interval", () => {
    it("fires fetch again after PING_INTERVAL_MS", async () => {
      vi.useFakeTimers()
      const { app } = await buildApp(okResponse)

      const callsBefore = fetch.mock.calls.length
      vi.advanceTimersByTime(PING_INTERVAL_MS)
      await Promise.resolve()

      expect(fetch.mock.calls.length).toBeGreaterThan(callsBefore)
      await teardownApp(app)
    })
  })

  // ── failure counting and offline marking ─────────────────────────────────────

  describe("failure counting", () => {
    it("does NOT set data-pito-cable-offline after 1 failure", async () => {
      vi.useFakeTimers()

      let pingCount = 0
      const { app } = await buildApp(() => {
        pingCount++
        // First ping succeeds, second fails (one failure total)
        return pingCount === 1 ? okResponse() : failResponse()
      })

      // Trigger the second ping (first failure)
      vi.advanceTimersByTime(PING_INTERVAL_MS)
      await Promise.resolve()
      await Promise.resolve()

      expect(document.body.hasAttribute("data-pito-cable-offline")).toBe(false)
      await teardownApp(app)
    })

    it("sets data-pito-cable-offline after 2 consecutive failures", async () => {
      vi.useFakeTimers()

      // All pings fail (connect-time ping = failure #1)
      const { app } = await buildApp(failResponse)

      // Second ping = failure #2 → offline
      vi.advanceTimersByTime(PING_INTERVAL_MS)
      await Promise.resolve()
      await Promise.resolve()

      expect(document.body.getAttribute("data-pito-cable-offline")).toBe("true")
      await teardownApp(app)
    })

    it("removes data-pito-cable-offline when a ping succeeds after offline state", async () => {
      vi.useFakeTimers()

      let pingCount = 0
      const { app } = await buildApp(() => {
        pingCount++
        return pingCount <= OFFLINE_THRESHOLD ? failResponse() : okResponse()
      })

      // First two failures → offline
      vi.advanceTimersByTime(PING_INTERVAL_MS)
      await Promise.resolve()
      await Promise.resolve()
      expect(document.body.hasAttribute("data-pito-cable-offline")).toBe(true)

      // Third ping succeeds → back online
      vi.advanceTimersByTime(PING_INTERVAL_MS)
      await Promise.resolve()
      await Promise.resolve()

      expect(document.body.hasAttribute("data-pito-cable-offline")).toBe(false)
      await teardownApp(app)
    })
  })

  // ── visibility-based reload ──────────────────────────────────────────────────

  describe("tab hidden → visible reload", () => {
    it("does NOT reload if tab was hidden for less than HIDDEN_RELOAD_MS", async () => {
      vi.useFakeTimers()
      const { app } = await buildApp(okResponse)

      // Record hiddenAt
      setVisibility("hidden")
      // Advance by LESS than the threshold (15s < 30s)
      vi.advanceTimersByTime(15000)
      // Restore visibility — wasHidden should be false
      setVisibility("visible")

      expect(window.location.reload).not.toHaveBeenCalled()
      await teardownApp(app)
    })

    it("reloads when tab was hidden for more than HIDDEN_RELOAD_MS", async () => {
      vi.useFakeTimers()
      // Pings succeed so this.online stays true (only wasHidden drives reload)
      const { app } = await buildApp(okResponse)

      setVisibility("hidden")
      // Advance past the threshold
      vi.advanceTimersByTime(PING_INTERVAL_MS + 1000)  // 31 s — also > HIDDEN_RELOAD_MS (30 s)
      setVisibility("visible")

      // wasHidden is true → reload was called
      expect(window.location.reload).toHaveBeenCalled()
      await teardownApp(app)
    })

    it("reloads on tab-show when already offline (short hidden time)", async () => {
      vi.useFakeTimers()

      // All pings fail → offline after 2
      const { app } = await buildApp(failResponse)

      // Two failures to enter offline state
      vi.advanceTimersByTime(PING_INTERVAL_MS)
      await Promise.resolve()
      await Promise.resolve()
      expect(document.body.hasAttribute("data-pito-cable-offline")).toBe(true)

      // Reset the reload spy so we only count calls from the visibility handler
      window.location.reload.mockClear()

      // Short hide (well under HIDDEN_RELOAD_MS) then show
      setVisibility("hidden")
      vi.advanceTimersByTime(100)
      setVisibility("visible")

      // Controller sees !this.online → reloads regardless of hidden duration
      expect(window.location.reload).toHaveBeenCalled()
      await teardownApp(app)
    })
  })
})
