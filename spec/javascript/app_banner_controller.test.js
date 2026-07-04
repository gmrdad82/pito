// spec/javascript/app_banner_controller.test.js
//
// Tests for pito/app_banner_controller.js — the "get the app" banner reveal /
// dismiss logic: the banner ships hidden, is revealed on connect only when no
// stored dismissal exists, and [x] hides it and persists the choice.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import AppBannerController from "controllers/pito/app_banner_controller"

// ── localStorage polyfill ─────────────────────────────────────────────────────
// jsdom's localStorage is unavailable for opaque origins. Provide a simple
// in-memory stub that matches the Storage interface used by the controller.
const _lsStore = {}
Object.defineProperty(window, "localStorage", {
  writable: true, configurable: true,
  value: {
    getItem:    (k) => Object.prototype.hasOwnProperty.call(_lsStore, k) ? _lsStore[k] : null,
    setItem:    (k, v) => { _lsStore[k] = String(v) },
    removeItem: (k) => { delete _lsStore[k] },
    clear:      () => { Object.keys(_lsStore).forEach((k) => delete _lsStore[k]) },
  }
})

const DISMISSED_KEY = "pito:app-banner-dismissed"

function buildDOM() {
  document.body.innerHTML = `
    <div class="hidden" data-controller="pito--app-banner">
      <button type="button" data-action="pito--app-banner#dismiss">[x]</button>
    </div>
  `
  return document.querySelector("[data-controller='pito--app-banner']")
}

describe("AppBannerController", () => {
  let app

  beforeEach(async () => {
    localStorage.clear()
    app = Application.start()
    app.register("pito--app-banner", AppBannerController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    localStorage.clear()
  })

  it("reveals the banner on connect when nothing was dismissed", async () => {
    const banner = buildDOM()
    await Promise.resolve()

    expect(banner.classList.contains("hidden")).toBe(false)
  })

  it("keeps the banner hidden when a dismissal is stored", async () => {
    localStorage.setItem(DISMISSED_KEY, "1")
    const banner = buildDOM()
    await Promise.resolve()

    expect(banner.classList.contains("hidden")).toBe(true)
  })

  it("hides the banner and persists the dismissal on dismiss", async () => {
    const banner = buildDOM()
    await Promise.resolve()

    banner.querySelector("button").click()

    expect(banner.classList.contains("hidden")).toBe(true)
    expect(localStorage.getItem(DISMISSED_KEY)).toBe("1")
  })
})
