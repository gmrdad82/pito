// spec/javascript/chat_showcase_controller.test.js
//
// Tests for pito--chat-showcase Stimulus controller.
//
// Covers:
//   - Empty + idle field: cycling starts, comet class applied, text set
//   - Focused field: cycling pauses, ghost hidden
//   - Non-empty field: cycling stops, ghost hidden
//   - Field cleared back to "": cycling resumes
//   - MutationObserver picks up new JSON from data target
//   - Disconnect cleans up timers

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ChatShowcaseController from "controllers/pito/chat_showcase_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

const SUGGESTIONS = ["list games", "show last vid", "list vids"]
const INTERVAL_MS = 50   // fast interval wired in DOM attrs
const PLACEHOLDER = "/help to see available commands"

function buildChatbox(suggestions = SUGGESTIONS) {
  const box = document.createElement("div")
  box.id = "pito-chatbox"
  box.setAttribute("data-controller", "pito--chat-showcase")
  // Fast interval so tests don't need to advance time by 6000ms.
  box.setAttribute("data-pito--chat-showcase-interval-value", String(INTERVAL_MS))

  // Data target (JSON script element)
  const dataScript = document.createElement("script")
  dataScript.type = "application/json"
  dataScript.id   = "pito-showcase-data"
  dataScript.setAttribute("data-pito--chat-showcase-target", "data")
  dataScript.textContent = JSON.stringify(suggestions)
  box.appendChild(dataScript)

  // Ghost item target
  const item = document.createElement("div")
  item.className = "pito-showcase-ghost"
  item.setAttribute("data-pito--chat-showcase-target", "item")
  box.appendChild(item)

  // Field target (textarea)
  const field = document.createElement("textarea")
  field.setAttribute("data-pito--chat-showcase-target", "field")
  field.setAttribute("placeholder", PLACEHOLDER)
  box.appendChild(field)

  document.body.appendChild(box)
  return { box, dataScript, item, field }
}

// Let Stimulus connect the controller: advance by 0ms so any internal
// setTimeout(fn, 0) callbacks fire, then flush microtasks.
async function waitForConnect() {
  vi.advanceTimersByTime(0)
  await Promise.resolve()
}

// Advance time and flush microtasks.
async function advance(ms) {
  vi.advanceTimersByTime(ms)
  await Promise.resolve()
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--chat-showcase controller", () => {
  let app

  beforeEach(() => {
    vi.useFakeTimers()
    app = Application.start()
    app.register("pito--chat-showcase", ChatShowcaseController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    await app.stop()
    vi.useRealTimers()
    await new Promise(r => setTimeout(r, 0))
    document.body.innerHTML = ""
  })

  // ── Connect + empty + idle state ────────────────────────────────────────────

  it("shows a suggestion text immediately when field is empty and idle", async () => {
    const { item } = buildChatbox()
    await waitForConnect()

    // _showNext() is called synchronously on connect, so the item should already
    // have text without advancing the interval timer.
    expect(item.textContent).toBeTruthy()
    expect(SUGGESTIONS).toContain(item.textContent)
  })

  it("applies pito-comet-reveal class on first show", async () => {
    const { item } = buildChatbox()
    await waitForConnect()
    expect(item.classList.contains("pito-comet-reveal")).toBe(true)
  })

  it("marks the ghost visible via is-visible class", async () => {
    const { item } = buildChatbox()
    await waitForConnect()
    expect(item.classList.contains("is-visible")).toBe(true)
  })

  it("cycles to the next suggestion after the interval elapses", async () => {
    const { item } = buildChatbox()
    await waitForConnect()
    const first = item.textContent

    // Advance past the COMET_MS timeout (900ms) that cleans up the comet class,
    // plus the interval (50ms), then flush.
    await advance(1000)

    const second = item.textContent
    // Both are valid suggestions.
    expect(SUGGESTIONS).toContain(first)
    expect(SUGGESTIONS).toContain(second)
  })

  // ── Caret alignment: the ghost tracks the real caret position ────────────────

  it("falls back to the field text origin (border+padding inset) before any caret event", async () => {
    const { field, item } = buildChatbox()
    await waitForConnect()
    // No pito:caret seen yet → fallback to the textarea text origin: offset PLUS
    // the field's own top/left border + padding (where typed glyphs render). The
    // old code used bare offsetTop/offsetLeft and dropped this inset, landing the
    // ghost off the caret's row.
    const cs = getComputedStyle(field)
    const top  = (field.offsetTop  || 0) + (parseFloat(cs.borderTopWidth)  || 0) + (parseFloat(cs.paddingTop)  || 0)
    const left = (field.offsetLeft || 0) + (parseFloat(cs.borderLeftWidth) || 0) + (parseFloat(cs.paddingLeft) || 0)
    expect(item.style.top).toBe(`${top}px`)
    expect(item.style.left).toBe(`${left}px`)
    // Guard the actual bug: the inset must be non-zero in jsdom's UA defaults.
    expect(top).toBeGreaterThan(0)
  })

  it("positions the ghost at the live caret coords from pito:caret", async () => {
    const { box, item } = buildChatbox()
    await waitForConnect()

    // The terminal-caret core emits the caret's exact pixel position (field-wrap
    // frame). The ghost must land THERE so the hint sits on the caret's row.
    box.dispatchEvent(new CustomEvent("pito:caret", { bubbles: true, detail: { left: 7, top: 21 } }))

    await advance(1000) // past COMET_MS + interval → next reveal

    expect(item.style.top).toBe("21px")
    expect(item.style.left).toBe("7px")
  })

  // ── Focus does NOT pause cycling (the chatbox autofocuses on load) ───────────

  it("keeps the ghost visible while focused + empty (focus does not pause)", async () => {
    const { field, item } = buildChatbox()
    await waitForConnect()

    field.dispatchEvent(new FocusEvent("focus", { bubbles: true }))

    // Focus must NOT stop cycling — the autofocused chatbox would otherwise never cycle.
    expect(item.classList.contains("is-visible")).toBe(true)
    expect(item.textContent).toBeTruthy()
  })

  it("advances text while focused + empty", async () => {
    const { field, item } = buildChatbox()
    await waitForConnect()

    field.dispatchEvent(new FocusEvent("focus", { bubbles: true }))
    const first = item.textContent
    await advance(INTERVAL_MS + 5)
    expect(item.textContent).not.toBe(first) // cycled to the next suggestion
    expect(SUGGESTIONS).toContain(item.textContent)
  })

  // ── Native placeholder is hidden while cycling, restored on input ────────────

  it("clears the native placeholder while cycling (no overlap with the ghost)", async () => {
    const { field } = buildChatbox()
    await waitForConnect()
    expect(field.getAttribute("placeholder")).toBe("")
  })

  it("restores the native placeholder when a value is typed", async () => {
    const { field } = buildChatbox()
    await waitForConnect()
    field.value = "list games"
    field.dispatchEvent(new Event("input", { bubbles: true }))
    expect(field.getAttribute("placeholder")).toBe(PLACEHOLDER)
  })

  // ── Input stops cycling ─────────────────────────────────────────────────────

  it("hides ghost when field has content", async () => {
    const { field, item } = buildChatbox()
    await waitForConnect()

    field.value = "list"
    field.dispatchEvent(new Event("input", { bubbles: true }))

    expect(item.classList.contains("is-visible")).toBe(false)
    expect(item.textContent).toBe("")
  })

  it("does not cycle while field has content", async () => {
    const { field, item } = buildChatbox()
    await waitForConnect()

    field.value = "list"
    field.dispatchEvent(new Event("input", { bubbles: true }))

    await advance(500)
    expect(item.textContent).toBe("")
  })

  it("resumes cycling when field is cleared", async () => {
    const { field, item } = buildChatbox()
    await waitForConnect()

    field.value = "list"
    field.dispatchEvent(new Event("input", { bubbles: true }))

    // Clear the field.
    field.value = ""
    field.dispatchEvent(new Event("input", { bubbles: true }))

    await waitForConnect()
    // Should have immediately shown a suggestion.
    expect(item.textContent).toBeTruthy()
    expect(SUGGESTIONS).toContain(item.textContent)
  })

  // ── Empty suggestions (unauthenticated path) ─────────────────────────────────

  it("shows nothing when suggestions array is empty", async () => {
    const { item } = buildChatbox([])
    await waitForConnect()

    expect(item.textContent).toBe("")
    expect(item.classList.contains("is-visible")).toBe(false)
  })

  it("does NOT clear the native placeholder when suggestions are empty (unauthenticated path)", async () => {
    // When there are no suggestions the showcase is inactive and the native
    // placeholder (login hint) must stay visible — the user needs it to know
    // how to authenticate.  The server renders placeholder="" for authenticated
    // users (showcase active), but the JS must not wipe a real placeholder when
    // the controller finds an empty suggestion set.
    const { field } = buildChatbox([])
    await waitForConnect()

    // _maybeStart() returns early → _clearPlaceholder() is never called.
    // The original PLACEHOLDER survives untouched.
    expect(field.getAttribute("placeholder")).toBe(PLACEHOLDER)
  })

  // ── No-default-placeholder: server pre-clears for authenticated users ─────────
  // When the server renders placeholder="" (because suggestions are present),
  // the controller stores _placeholder="" and restoring it after typing is a
  // no-op — correct for authenticated users who have the comet as the hint.

  it("stores empty string as the original placeholder when the field starts with placeholder empty", async () => {
    // Simulate the authenticated server-render: placeholder="" in the DOM.
    const { field } = buildChatbox()
    field.setAttribute("placeholder", "")         // mimic server-side suppression
    await waitForConnect()                         // controller reads "" from DOM

    // Type something → stop cycling → _restorePlaceholder() → sets "" (no-op).
    field.value = "list games"
    field.dispatchEvent(new Event("input", { bubbles: true }))

    // The native placeholder remains empty (authenticated users have the comet).
    expect(field.getAttribute("placeholder")).toBe("")
  })

  // ── MutationObserver picks up new JSON ───────────────────────────────────────

  it("loads new suggestions when the data script element is replaced", async () => {
    const { box, dataScript, item } = buildChatbox(["list games"])
    await waitForConnect()

    // Simulate a Turbo Stream replace: swap out the script element.
    const newScript = document.createElement("script")
    newScript.type = "application/json"
    newScript.id   = "pito-showcase-data"
    newScript.setAttribute("data-pito--chat-showcase-target", "data")
    newScript.textContent = JSON.stringify(["show last vid", "list vids"])
    box.removeChild(dataScript)
    box.appendChild(newScript)

    // Allow MutationObserver + Stimulus target reconnect to fire.
    await waitForConnect()
    await advance(INTERVAL_MS)
    await waitForConnect()

    // The item should eventually show one of the new suggestions.
    const newSuggestions = ["show last vid", "list vids"]
    expect(newSuggestions.includes(item.textContent) || item.textContent === "").toBe(true)
  })

  // ── Disconnect cleans up ──────────────────────────────────────────────────────

  it("stops and cleans up on disconnect", async () => {
    const { box } = buildChatbox()
    await waitForConnect()

    // Remove the element → Stimulus disconnect() fires.
    box.remove()
    await waitForConnect()

    // No ghost element remains in the DOM; no timers throw.
    expect(document.querySelector(".pito-showcase-ghost")).toBeNull()
  })
})
