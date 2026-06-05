// spec/javascript/auth.test.js
//
// Vitest suite for pito/auth.js — isAuthenticated()
//
// The function reads #pito-auth-gate[data-authenticated] and returns
// true  when the attribute value is exactly the string "true",
// false in every other case (missing element, missing attribute,
// attribute value "false", blank, etc.).
//
// No Stimulus wiring needed — this is a plain ES module export.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { isAuthenticated } from "pito/auth"

// ── Helpers ───────────────────────────────────────────────────────────────────

function ensureNoGate() {
  const existing = document.getElementById("pito-auth-gate")
  if (existing) existing.remove()
}

function addGate(dataAuthenticated) {
  const el = document.createElement("div")
  el.id = "pito-auth-gate"
  if (dataAuthenticated !== undefined) {
    el.dataset.authenticated = dataAuthenticated
  }
  document.body.appendChild(el)
  return el
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("isAuthenticated()", () => {
  beforeEach(() => {
    ensureNoGate()
  })

  afterEach(() => {
    ensureNoGate()
  })

  // ── true branch ─────────────────────────────────────────────────────────────

  describe('data-authenticated="true"', () => {
    it("returns true when the gate element has data-authenticated=true", () => {
      addGate("true")
      expect(isAuthenticated()).toBe(true)
    })
  })

  // ── false branch ────────────────────────────────────────────────────────────

  describe('data-authenticated="false"', () => {
    it("returns false when data-authenticated is the string false", () => {
      addGate("false")
      expect(isAuthenticated()).toBe(false)
    })
  })

  describe("missing data-authenticated attribute", () => {
    it("returns false when the attribute is absent", () => {
      addGate(undefined)   // element exists but no dataset.authenticated
      expect(isAuthenticated()).toBe(false)
    })
  })

  describe("missing gate element", () => {
    it("returns false when #pito-auth-gate does not exist in the DOM", () => {
      // ensureNoGate() already removed it; no addGate() call here.
      expect(isAuthenticated()).toBe(false)
    })
  })

  describe("edge-case attribute values", () => {
    it("returns false for an empty string value", () => {
      addGate("")
      expect(isAuthenticated()).toBe(false)
    })

    it("returns false for the string '1' (not exactly 'true')", () => {
      addGate("1")
      expect(isAuthenticated()).toBe(false)
    })

    it("returns false for the string 'True' (case-sensitive check)", () => {
      addGate("True")
      expect(isAuthenticated()).toBe(false)
    })

    it("returns false for the string 'yes'", () => {
      addGate("yes")
      expect(isAuthenticated()).toBe(false)
    })
  })
})
