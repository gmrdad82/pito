// spec/javascript/auto_visit_controller.test.js
//
// Tests for pito--auto-visit Stimulus controller.
//
// Covers:
//   - After the delay, pito-shimmer is removed from the copy target.
//   - After the delay, the link target is clicked (opening the YouTube page).
//   - When hasLinkTarget is false, falls back to document.getElementById.
//   - Timer is cleared on disconnect (no stale click after element removed).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import AutoVisitController from "controllers/pito/auto_visit_controller"

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildDOM({ delay = 1000, linkId = "visit-link-1" } = {}) {
  const div = document.createElement("div")
  div.setAttribute("data-controller", "pito--auto-visit")
  div.setAttribute("data-pito--auto-visit-delay-value", String(delay))
  div.setAttribute("data-pito--auto-visit-link-id-value", linkId)

  const copy = document.createElement("span")
  copy.setAttribute("data-pito--auto-visit-target", "copy")
  copy.classList.add("pito-shimmer")
  copy.textContent = "Visiting @alpha..."
  div.appendChild(copy)

  const link = document.createElement("a")
  link.id = linkId
  link.href = "https://www.youtube.com/@alpha"
  link.setAttribute("data-pito--auto-visit-target", "link")
  link.classList.add("hidden")
  div.appendChild(link)

  document.body.appendChild(div)
  return { div, copy, link }
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--auto-visit controller", () => {
  let app

  beforeEach(() => {
    vi.useFakeTimers()
    app = Application.start()
    app.register("pito--auto-visit", AutoVisitController)
  })

  afterEach(async () => {
    vi.clearAllTimers()
    if (app) await app.stop()
    document.body.innerHTML = ""
    vi.useRealTimers()
  })

  it("removes pito-shimmer from the copy target after the delay", async () => {
    const { copy } = buildDOM({ delay: 1000 })
    await Promise.resolve()

    expect(copy.classList.contains("pito-shimmer")).toBe(true)

    vi.advanceTimersByTime(999)
    expect(copy.classList.contains("pito-shimmer")).toBe(true)

    vi.advanceTimersByTime(1)
    expect(copy.classList.contains("pito-shimmer")).toBe(false)
  })

  it("calls click() on the link target after the delay", async () => {
    const { link } = buildDOM({ delay: 1000 })
    await Promise.resolve()

    const clickSpy = vi.spyOn(link, "click")

    vi.advanceTimersByTime(999)
    expect(clickSpy).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(clickSpy).toHaveBeenCalledOnce()
  })

  it("falls back to document.getElementById when no link target", async () => {
    // Build DOM without the data-pito--auto-visit-target="link" attr
    const div = document.createElement("div")
    div.setAttribute("data-controller", "pito--auto-visit")
    div.setAttribute("data-pito--auto-visit-delay-value", "500")
    div.setAttribute("data-pito--auto-visit-link-id-value", "fallback-link")

    const copy = document.createElement("span")
    copy.setAttribute("data-pito--auto-visit-target", "copy")
    copy.classList.add("pito-shimmer")
    div.appendChild(copy)

    // Link exists in DOM but NOT as a Stimulus target
    const link = document.createElement("a")
    link.id = "fallback-link"
    link.href = "https://www.youtube.com/@beta"
    document.body.appendChild(link)
    document.body.appendChild(div)

    await Promise.resolve()

    const clickSpy = vi.spyOn(link, "click")
    vi.advanceTimersByTime(500)
    expect(clickSpy).toHaveBeenCalledOnce()
  })

  it("does not click after disconnect", async () => {
    const { div, link } = buildDOM({ delay: 1000 })
    await Promise.resolve()

    const clickSpy = vi.spyOn(link, "click")

    // Disconnect before the timer fires
    div.removeAttribute("data-controller")
    div.remove()
    await Promise.resolve()

    vi.advanceTimersByTime(2000)
    expect(clickSpy).not.toHaveBeenCalled()
  })
})
