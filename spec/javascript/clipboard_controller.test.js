// spec/javascript/clipboard_controller.test.js
//
// Tests for pito/clipboard_controller.js
//
// Covers:
//   1. copy() calls navigator.clipboard.writeText with the textValue.
//   2. flashFeedback() changes feedbackTarget text to "Copied!" then restores it.
//   3. fallbackCopy() is used when clipboard API rejects.
//
// jsdom supports navigator.clipboard via vi.stubGlobal / vi.spyOn.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ClipboardController from "controllers/pito/clipboard_controller"

// ── Setup ─────────────────────────────────────────────────────────────────────

function buildDOM(text = "hello world") {
  document.body.innerHTML = `
    <div
      data-controller="pito--clipboard"
      data-pito--clipboard-text-value="${text}"
    >
      <button data-action="click->pito--clipboard#copy">Copy</button>
      <span data-pito--clipboard-target="feedback">Copy text</span>
    </div>
  `
  return document.querySelector("[data-controller='pito--clipboard']")
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("ClipboardController", () => {
  let app
  let writeTextMock

  beforeEach(async () => {
    vi.useFakeTimers()

    // Stub navigator.clipboard
    writeTextMock = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: writeTextMock },
      configurable: true,
      writable: true,
    })

    app = Application.start()
    app.register("pito--clipboard", ClipboardController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  describe("copy()", () => {
    it("calls navigator.clipboard.writeText with the configured text", async () => {
      buildDOM("copy me")
      await Promise.resolve()

      const btn = document.querySelector("button")
      btn.click()
      await Promise.resolve()

      expect(writeTextMock).toHaveBeenCalledWith("copy me")
    })

    it("does not call writeText when textValue is empty", async () => {
      buildDOM("")
      await Promise.resolve()

      const btn = document.querySelector("button")
      btn.click()
      await Promise.resolve()

      expect(writeTextMock).not.toHaveBeenCalled()
    })
  })

  describe("flashFeedback()", () => {
    it("changes feedback text to 'Copied!' immediately after copy", async () => {
      buildDOM("text")
      await Promise.resolve()

      document.querySelector("button").click()
      // Resolve the clipboard promise.
      await Promise.resolve()
      await Promise.resolve()

      const feedback = document.querySelector("[data-pito--clipboard-target='feedback']")
      expect(feedback.textContent).toBe("Copied!")
    })

    it("adds text-success class during the flash", async () => {
      buildDOM("text")
      await Promise.resolve()

      document.querySelector("button").click()
      await Promise.resolve()
      await Promise.resolve()

      const feedback = document.querySelector("[data-pito--clipboard-target='feedback']")
      expect(feedback.classList.contains("text-success")).toBe(true)
    })

    it("restores original text after 1500 ms", async () => {
      buildDOM("text")
      await Promise.resolve()

      const feedback = document.querySelector("[data-pito--clipboard-target='feedback']")
      const originalText = feedback.textContent  // "Copy text"

      document.querySelector("button").click()
      await Promise.resolve()
      await Promise.resolve()

      vi.advanceTimersByTime(1500)

      expect(feedback.textContent).toBe(originalText)
      expect(feedback.classList.contains("text-success")).toBe(false)
    })
  })

  describe("fallbackCopy()", () => {
    beforeEach(() => {
      // Make the clipboard API reject to trigger the fallback path.
      writeTextMock.mockRejectedValue(new Error("not allowed"))
    })

    it("falls back gracefully without throwing when clipboard API is unavailable", async () => {
      buildDOM("fallback text")
      await Promise.resolve()

      expect(() => {
        document.querySelector("button").click()
      }).not.toThrow()
    })
  })
})
