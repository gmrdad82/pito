// spec/javascript/settings.test.js
//
// Tests for pito/settings.js
//
// soundEnabled() fails open: missing element or attribute → true.
// (fxEnabled/fxEffect/motionDisabled were removed in item 18.)

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { soundEnabled } from "pito/settings"

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

describe("pito/settings", () => {
  beforeEach(() => { ensureNoSettings() })
  afterEach(()  => { ensureNoSettings() })

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
})
