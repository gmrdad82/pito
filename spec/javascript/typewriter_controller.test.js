// spec/javascript/typewriter_controller.test.js
//
// Tests for the pito--typewriter controller (typewriter_controller.js).
//
// Strategy: mount the real controller on a jsdom segment with a `body` target
// plus several `prose` targets, then assert it collects + reveals ALL of them.
//
// Regression guard: the controller must use the singular Stimulus getter
// `hasProseTarget` (not `hasProseTargets`) — the plural is `undefined`, which
// once silently disabled prose collection so only the body animated. The
// "blanks all prose targets on connect" test fails if that collection branch
// is skipped.
//
// htmlProse targets: HTML cells (e.g. platform logo spans) carry the
// `htmlProse` target so the controller can hide them at connect and reveal
// them in DOM order during the animation sequence — preventing logos from
// popping in immediately while text cells are still being typed out.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import TypewriterController from "controllers/pito/typewriter_controller"

// Build a typewriter segment: one body target + N prose targets.
function buildSegment(bodyText, proseTexts = []) {
  const div = document.createElement("div")
  div.setAttribute("data-controller", "pito--typewriter")

  const body = document.createElement("span")
  body.setAttribute("data-pito--typewriter-target", "body")
  body.textContent = bodyText
  div.appendChild(body)

  const proses = proseTexts.map((t) => {
    const p = document.createElement("span")
    p.setAttribute("data-pito--typewriter-target", "prose")
    p.textContent = t
    div.appendChild(p)
    return p
  })

  document.body.appendChild(div)
  return { div, body, proses }
}

// Build a segment with mixed prose and htmlProse targets (mirrors the platform
// logo use-case: body + some prose text cells + one html logo cell).
function buildSegmentWithHtmlProse(bodyText, proseTexts = [], htmlContents = []) {
  const div = document.createElement("div")
  div.setAttribute("data-controller", "pito--typewriter")

  const body = document.createElement("span")
  body.setAttribute("data-pito--typewriter-target", "body")
  body.textContent = bodyText
  div.appendChild(body)

  proseTexts.forEach((t) => {
    const p = document.createElement("span")
    p.setAttribute("data-pito--typewriter-target", "prose")
    p.textContent = t
    div.appendChild(p)
  })

  const htmlEls = htmlContents.map((html) => {
    const p = document.createElement("span")
    p.setAttribute("data-pito--typewriter-target", "htmlProse")
    p.innerHTML = html
    div.appendChild(p)
    return p
  })

  document.body.appendChild(div)
  return { div, htmlEls }
}

describe("pito--typewriter controller", () => {
  let app

  beforeEach(() => {
    // jsdom has no matchMedia; the controller calls it in #skipAnimation.
    window.matchMedia = () => ({ matches: false })
    // Live arrival (so the controller animates rather than rendering instant).
    window.__pitoReady = true
    // No #pito-settings element → fxEnabled() fails open (true).

    app = Application.start()
    app.register("pito--typewriter", TypewriterController)
  })

  afterEach(async () => {
    await app.stop() // disconnect() cancels + restores + drains the reveal queue
    document.body.innerHTML = ""
    delete window.__pitoReady
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  it("blanks the body AND every prose target on connect (regression: prose collection)", async () => {
    const { body, proses } = buildSegment("hello world", ["SECTION", "key", "value"])
    await waitForConnect()

    expect(body.textContent).toBe("")
    expect(proses.map((p) => p.textContent)).toEqual(["", "", ""])
  })

  it("reveals the body and all prose targets to their full text", async () => {
    const { body, proses } = buildSegment("hi", ["xy", "z"])
    await waitForConnect()
    // Small texts type out well within this window (TICK_MS=12, CHARS_TICK=2).
    await new Promise((r) => setTimeout(r, 400))

    expect(body.textContent).toBe("hi")
    expect(proses.map((p) => p.textContent)).toEqual(["xy", "z"])
  })

  it("does not animate (no blanking) on the initial server render (__pitoReady falsy)", async () => {
    window.__pitoReady = false
    const { body, proses } = buildSegment("hello", ["AAA"])
    await waitForConnect()

    expect(body.textContent).toBe("hello")
    expect(proses[0].textContent).toBe("AAA")
  })

  it("animates the body even when there are no prose targets", async () => {
    const { body } = buildSegment("just a body")
    await waitForConnect()

    expect(body.textContent).toBe("")
    await new Promise((r) => setTimeout(r, 400))
    expect(body.textContent).toBe("just a body")
  })

  describe("htmlProse targets — reveal gating for HTML cells (platform logos)", () => {
    it("hides htmlProse targets immediately on connect (before animation starts)", async () => {
      const { htmlEls } = buildSegmentWithHtmlProse("body text", ["prose text"], ["<img src='ps.svg'>"])
      await waitForConnect()

      // Hidden synchronously in connect() before the reveal job runs.
      expect(htmlEls[0].style.visibility).toBe("hidden")
    })

    it("reveals htmlProse targets after animation completes", async () => {
      const { htmlEls } = buildSegmentWithHtmlProse("hi", ["ok"], ["<img src='ps.svg'>"])
      await waitForConnect()
      // Wait for animation to finish (TICK_MS=12, short texts done well within 400ms).
      await new Promise((r) => setTimeout(r, 400))

      expect(htmlEls[0].style.visibility).toBe("")
    })

    it("reveals htmlProse targets in instant mode (backpressure / __pitoReady false)", async () => {
      window.__pitoReady = false
      const { htmlEls } = buildSegmentWithHtmlProse("body", [], ["<img src='icon.svg'>"])
      await waitForConnect()

      // No controller connected (skipAnimation returned early) — element unmodified.
      expect(htmlEls[0].style.visibility).toBe("")
    })

    it("does NOT hide htmlProse targets when animation is skipped (__pitoReady falsy)", async () => {
      window.__pitoReady = false
      const { htmlEls } = buildSegmentWithHtmlProse("hello", ["world"], ["<img src='x.svg'>"])
      await waitForConnect()

      expect(htmlEls[0].style.visibility).not.toBe("hidden")
    })
  })
})
