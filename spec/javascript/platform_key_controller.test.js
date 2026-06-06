// spec/javascript/platform_key_controller.test.js
//
// Tests for pito/platform_key_controller.js
//
// On Mac: replaces element textContent with `mac` value on connect().
// On non-Mac: leaves textContent unchanged.
//
// We stub navigator.platform (or userAgentData.platform) via Object.defineProperty.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import PlatformKeyController from "controllers/pito/platform_key_controller"

// ── Setup ─────────────────────────────────────────────────────────────────────

function buildDOM(macValue = "Cmd+K", defaultText = "Ctrl+K") {
  document.body.innerHTML = `
    <span
      data-controller="pito--platform-key"
      data-pito--platform-key-mac-value="${macValue}"
    >${defaultText}</span>
  `
  return document.querySelector("[data-controller='pito--platform-key']")
}

function stubPlatform(platform) {
  // Prefer userAgentData (modern) but jsdom may not have it.
  if (navigator.userAgentData) {
    vi.spyOn(navigator.userAgentData, "platform", "get").mockReturnValue(platform)
  } else {
    Object.defineProperty(navigator, "platform", {
      value: platform,
      configurable: true,
    })
  }
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("PlatformKeyController", () => {
  let app

  beforeEach(async () => {
    app = Application.start()
    app.register("pito--platform-key", PlatformKeyController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
    // Clean up any defineProperty override.
    try {
      Object.defineProperty(navigator, "platform", { value: "", configurable: true })
    } catch (_) { /* ignore */ }
  })

  describe("Mac platform", () => {
    beforeEach(() => { stubPlatform("MacIntel") })

    it("replaces textContent with the mac value on connect", async () => {
      buildDOM("Cmd+K", "Ctrl+K")
      await Promise.resolve()
      const el = document.querySelector("[data-controller='pito--platform-key']")
      expect(el.textContent).toBe("Cmd+K")
    })

    it("works for iPhone platform string", async () => {
      stubPlatform("iPhone")
      buildDOM("Cmd+P", "Ctrl+P")
      await Promise.resolve()
      const el = document.querySelector("[data-controller='pito--platform-key']")
      expect(el.textContent).toBe("Cmd+P")
    })
  })

  describe("non-Mac platform (Win32 / Linux)", () => {
    beforeEach(() => { stubPlatform("Win32") })

    it("leaves textContent unchanged on Windows", async () => {
      buildDOM("Cmd+K", "Ctrl+K")
      await Promise.resolve()
      const el = document.querySelector("[data-controller='pito--platform-key']")
      expect(el.textContent).toBe("Ctrl+K")
    })

    it("leaves textContent unchanged on Linux", async () => {
      stubPlatform("Linux x86_64")
      buildDOM("Cmd+K", "Ctrl+K")
      await Promise.resolve()
      const el = document.querySelector("[data-controller='pito--platform-key']")
      expect(el.textContent).toBe("Ctrl+K")
    })
  })
})
