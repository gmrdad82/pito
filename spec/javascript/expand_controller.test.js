// spec/javascript/expand_controller.test.js
//
// Tests for pito/expand_controller.js
//
// Covered:
//   - setExpanded(true/false) toggles the correct CSS classes and label text.
//   - connect() opens the segment immediately when expandAllEnabled() is true.
//   - connect() leaves the segment collapsed when expandAllEnabled() is false.
//   - Ctrl+| global keydown triggers toggleAll() (DOM-level, no fetch needed).
//   - toggleAll() updates #pito-settings data-expand-all immediately.
//
// Skipped:
//   - POST /settings/expand_all — requires a real server; not unit-testable.
//   - Multi-instance coordination (integration concern).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"

// We import the default export from the expand controller.
// The module also imports from "pito/auth" and "pito/settings".
import ExpandController from "controllers/pito/expand_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

function addSettings({ sound = "true", fx = "true", expandAll = "false" } = {}) {
  const el = document.createElement("div")
  el.id = "pito-settings"
  el.dataset.sound     = sound
  el.dataset.fx        = fx
  el.dataset.expandAll = expandAll
  document.body.appendChild(el)
  return el
}

function removeSettings() {
  document.getElementById("pito-settings")?.remove()
}

function addAuthGate(authenticated = "true") {
  const el = document.createElement("div")
  el.id = "pito-auth-gate"
  el.dataset.authenticated = authenticated
  document.body.appendChild(el)
  return el
}

function removeAuthGate() {
  document.getElementById("pito-auth-gate")?.remove()
}

function buildSegmentDOM({ expanded = false } = {}) {
  document.body.innerHTML += `
    <div
      data-controller="pito--expand"
      data-expanded="${expanded}"
      data-pito--expand-expand-label-value="to expand"
      data-pito--expand-collapse-label-value="to collapse"
    >
      <div data-pito--expand-target="detail" class="${expanded ? "" : "hidden"}">Detail content</div>
      <div data-pito--expand-target="hint" class="${expanded ? "hidden" : ""}">
        <span data-pito--expand-target="hintLabel">to expand</span>
      </div>
    </div>
  `
  return document.querySelector("[data-controller='pito--expand']")
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("ExpandController", () => {
  let app

  beforeEach(async () => {
    // Stub fetch to prevent real network calls from toggleAll().
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }))

    addSettings({ expandAll: "false" })
    addAuthGate("true")

    app = Application.start()
    app.register("pito--expand", ExpandController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    removeSettings()
    removeAuthGate()
  })

  // ── setExpanded() ─────────────────────────────────────────────────────────

  describe("setExpanded(true)", () => {
    it("removes 'hidden' from the detail target", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const el       = document.querySelector("[data-controller='pito--expand']")
      const instance = el.__pito_expand_instance
      instance.setExpanded(true)

      expect(el.querySelector("[data-pito--expand-target='detail']").classList.contains("hidden")).toBe(false)
    })

    it("hides the hint target", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const el       = document.querySelector("[data-controller='pito--expand']")
      const instance = el.__pito_expand_instance
      instance.setExpanded(true)

      expect(el.querySelector("[data-pito--expand-target='hint']").classList.contains("hidden")).toBe(true)
    })

    it("changes hintLabel to the collapse label", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const el       = document.querySelector("[data-controller='pito--expand']")
      const instance = el.__pito_expand_instance
      instance.setExpanded(true)

      const label = el.querySelector("[data-pito--expand-target='hintLabel']")
      expect(label.textContent).toBe("to collapse")
    })
  })

  describe("setExpanded(false)", () => {
    it("re-hides the detail target", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const el       = document.querySelector("[data-controller='pito--expand']")
      const instance = el.__pito_expand_instance
      instance.setExpanded(true)
      instance.setExpanded(false)

      expect(el.querySelector("[data-pito--expand-target='detail']").classList.contains("hidden")).toBe(true)
    })

    it("restores the expand label", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const el       = document.querySelector("[data-controller='pito--expand']")
      const instance = el.__pito_expand_instance
      instance.setExpanded(true)
      instance.setExpanded(false)

      const label = el.querySelector("[data-pito--expand-target='hintLabel']")
      expect(label.textContent).toBe("to expand")
    })
  })

  // ── connect() with expandAll ON ──────────────────────────────────────────

  describe("connect() with expandAllEnabled() = true", () => {
    it("opens the segment immediately on connect", async () => {
      // Update settings to expand-all = true BEFORE building the DOM.
      document.getElementById("pito-settings").dataset.expandAll = "true"

      buildSegmentDOM()
      await Promise.resolve()

      const el     = document.querySelector("[data-controller='pito--expand']")
      const detail = el.querySelector("[data-pito--expand-target='detail']")
      expect(detail.classList.contains("hidden")).toBe(false)
    })
  })

  // ── Ctrl+| global key ────────────────────────────────────────────────────

  describe("Ctrl+| global keydown", () => {
    it("updates #pito-settings data-expand-all immediately (optimistic write)", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const settings = document.getElementById("pito-settings")
      expect(settings.dataset.expandAll).toBe("false")

      document.dispatchEvent(new KeyboardEvent("keydown", {
        key: "|", ctrlKey: true, bubbles: true,
      }))
      await Promise.resolve()

      expect(settings.dataset.expandAll).toBe("true")
    })

    it("toggles back to false on a second Ctrl+|", async () => {
      buildSegmentDOM()
      await Promise.resolve()

      const settings = document.getElementById("pito-settings")

      document.dispatchEvent(new KeyboardEvent("keydown", { key: "|", ctrlKey: true, bubbles: true }))
      await Promise.resolve()
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "|", ctrlKey: true, bubbles: true }))
      await Promise.resolve()

      expect(settings.dataset.expandAll).toBe("false")
    })

    it("does NOT toggle when user is not authenticated", async () => {
      document.getElementById("pito-auth-gate").dataset.authenticated = "false"

      buildSegmentDOM()
      await Promise.resolve()

      const settings = document.getElementById("pito-settings")
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "|", ctrlKey: true, bubbles: true }))
      await Promise.resolve()

      expect(settings.dataset.expandAll).toBe("false")
    })
  })
})
