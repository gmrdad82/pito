// spec/javascript/settings.test.js
//
// Tests for pito/settings.js
//
// soundEnabled() and fxEnabled() fail-open: missing element or attribute → true.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { soundEnabled, fxEnabled } from "pito/settings"

// ── Helpers ──────────────────────────────────────────────────────────────────

function ensureNoSettings() {
  document.getElementById("pito-settings")?.remove()
}

function addSettings(dataset = {}) {
  const el = document.createElement("div")
  el.id = "pito-settings"
  for (const [key, value] of Object.entries(dataset)) {
    el.dataset[key] = value
  }
  document.body.appendChild(el)
  return el
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito/settings", () => {
  beforeEach(() => { ensureNoSettings() })
  afterEach(()  => { ensureNoSettings() })

  // ── soundEnabled() ───────────────────────────────────────────────────────

  describe("soundEnabled()", () => {
    it("returns true when element is absent (fail-open)", () => {
      expect(soundEnabled()).toBe(true)
    })

    it("returns true when data-sound attribute is absent", () => {
      addSettings({})
      expect(soundEnabled()).toBe(true)
    })

    it("returns true when data-sound is 'true'", () => {
      addSettings({ sound: "true" })
      expect(soundEnabled()).toBe(true)
    })

    it("returns false when data-sound is 'false'", () => {
      addSettings({ sound: "false" })
      expect(soundEnabled()).toBe(false)
    })

    it("returns true for any value that is not exactly 'false'", () => {
      addSettings({ sound: "1" })
      expect(soundEnabled()).toBe(true)
    })
  })

  // ── fxEnabled() ─────────────────────────────────────────────────────────

  describe("fxEnabled()", () => {
    it("returns true when element is absent (fail-open)", () => {
      expect(fxEnabled()).toBe(true)
    })

    it("returns true when data-fx attribute is absent", () => {
      addSettings({})
      expect(fxEnabled()).toBe(true)
    })

    it("returns true when data-fx is 'true'", () => {
      addSettings({ fx: "true" })
      expect(fxEnabled()).toBe(true)
    })

    it("returns false when data-fx is 'false'", () => {
      addSettings({ fx: "false" })
      expect(fxEnabled()).toBe(false)
    })

    it("returns true for any value that is not exactly 'false'", () => {
      addSettings({ fx: "0" })
      expect(fxEnabled()).toBe(true)
    })
  })
})
