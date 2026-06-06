// spec/javascript/settings.test.js
//
// Tests for pito/settings.js
//
// soundEnabled() and fxEnabled() fail-open: missing element or attribute → true.
// expandAllEnabled() fails-closed: missing element or attribute → false.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { soundEnabled, fxEnabled, expandAllEnabled } from "pito/settings"

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

  // ── expandAllEnabled() ───────────────────────────────────────────────────

  describe("expandAllEnabled()", () => {
    it("returns false when element is absent (fail-closed)", () => {
      expect(expandAllEnabled()).toBe(false)
    })

    it("returns false when data-expand-all attribute is absent", () => {
      addSettings({})
      expect(expandAllEnabled()).toBe(false)
    })

    it("returns true when data-expand-all is 'true'", () => {
      addSettings({ expandAll: "true" })
      expect(expandAllEnabled()).toBe(true)
    })

    it("returns false when data-expand-all is 'false'", () => {
      addSettings({ expandAll: "false" })
      expect(expandAllEnabled()).toBe(false)
    })

    it("returns false for value '1' (not exactly 'true')", () => {
      addSettings({ expandAll: "1" })
      expect(expandAllEnabled()).toBe(false)
    })

    it("returns false for value 'True' (case-sensitive)", () => {
      addSettings({ expandAll: "True" })
      expect(expandAllEnabled()).toBe(false)
    })
  })
})
