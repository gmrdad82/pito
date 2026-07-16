// spec/javascript/anchor_jump_controller.test.js
//
// Vitest suite for pito--anchor-jump Stimulus controller.
//
// The controller delegates a single `click` listener on `document` (mirrors
// pito--selection-scope's document-level binding — see
// selection_scope_controller.test.js). On click it walks up via
// `closest("[data-anchor-event-id]")` to find a hit-row cell, resolves the
// matching `#event_<id>` element, scrolls it into view, and stamps it with a
// 2s `pito-anchor-flash` class. The timeout lives on the TARGET element
// (`target._pitoAnchorFlashTimeout`), not the controller, so two flashes on
// different targets must clean up independently. It also stamps a
// PERSISTENT `pito-anchor-highlight` class (no timeout) on the target,
// removing it from wherever it previously lived first — only one message
// carries the marker at a time.
//
// Covers:
//   • Click inside a hit row (even on a nested child) scrolls the matching
//     event with { behavior: "smooth", block: "start" } and adds the flash class
//   • The flash class is removed after the 2s timeout (fake timers)
//   • A second jump to a DIFFERENT target while the first flash is still live
//     cleans up both independently — no stuck class
//   • A hit row whose event id has no matching element in this DOM (e.g. a
//     cross-conversation hit) is a graceful no-op: no scroll call, no crash,
//     and the delegated listener keeps working afterward
//   • A click outside any hit row is a no-op
//   • jumpToEvent adds the persistent pito-anchor-highlight class to the target
//   • A second jumpToEvent to a different event moves the persistent marker
//     (removed from the first target, present on the second)

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import AnchorJumpController from "controllers/pito/anchor_jump_controller"

// jsdom does not implement scrollIntoView — stub a no-op on the prototype so
// the controller's call doesn't throw; individual tests spy on it (either on
// a specific target element or on the prototype) to assert on calls.
if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = function () {}
}

// ── DOM scaffold ─────────────────────────────────────────────────────────────

// The controller listens on `document`, not `this.element` — any element
// carrying the data-controller attribute is enough to connect it.
function buildScaffold() {
  const container = document.createElement("div")
  container.setAttribute("data-controller", "pito--anchor-jump")
  document.body.appendChild(container)
  return container
}

// A hit-row cell stamped with data-anchor-event-id, appended directly to
// <body> — mirroring how a search-hit row can render inside ANY system
// message, not necessarily inside the controller's own mount point.
function addHitRow(eventId) {
  const row = document.createElement("div")
  row.className = "hit-row"
  const cell = document.createElement("span")
  cell.setAttribute("data-anchor-event-id", String(eventId))
  cell.textContent = `#${eventId}`
  row.appendChild(cell)
  document.body.appendChild(row)
  return { row, cell }
}

function addTargetEvent(eventId) {
  const el = document.createElement("div")
  el.id = `event_${eventId}`
  document.body.appendChild(el)
  return el
}

function click(el) {
  el.dispatchEvent(new MouseEvent("click", { bubbles: true }))
}

function tick(ms = 20) {
  return new Promise((r) => setTimeout(r, ms))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--anchor-jump controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--anchor-jump", AnchorJumpController)
  })

  afterEach(async () => {
    vi.useRealTimers()
    // Stimulus stop() only pauses observation — it never disconnects live
    // controllers, so a document-delegated listener would leak into the
    // next test. Remove the controller's element FIRST and let the
    // MutationObserver deliver the disconnect before stopping.
    document.body.innerHTML = ""
    await new Promise((r) => setTimeout(r, 0))
    await app.stop()
    vi.restoreAllMocks()
  })

  it("clicking inside a hit row scrolls the matching event and adds the flash class", async () => {
    buildScaffold()
    const target = addTargetEvent(42)
    const { cell } = addHitRow(42)
    // A nested child with no attribute of its own — proves closest() bubbles
    // up through descendants of the stamped cell, not just the cell itself.
    const inner = document.createElement("b")
    inner.textContent = "#42"
    cell.appendChild(inner)

    const scrollSpy = vi.spyOn(target, "scrollIntoView")

    await tick()
    click(inner)

    expect(scrollSpy).toHaveBeenCalledTimes(1)
    expect(scrollSpy).toHaveBeenCalledWith({ behavior: "smooth", block: "start" })
    expect(target.classList.contains("pito-anchor-flash")).toBe(true)
    expect(target.classList.contains("pito-anchor-highlight")).toBe(true)
  })

  it("moves the persistent highlight marker on a second jump to a different event", async () => {
    buildScaffold()
    const targetA = addTargetEvent(10)
    const targetB = addTargetEvent(20)
    const { cell: cellA } = addHitRow(10)
    const { cell: cellB } = addHitRow(20)
    vi.spyOn(targetA, "scrollIntoView")
    vi.spyOn(targetB, "scrollIntoView")

    await tick()

    click(cellA)
    expect(targetA.classList.contains("pito-anchor-highlight")).toBe(true)
    expect(targetB.classList.contains("pito-anchor-highlight")).toBe(false)

    click(cellB)
    expect(targetA.classList.contains("pito-anchor-highlight")).toBe(false)
    expect(targetB.classList.contains("pito-anchor-highlight")).toBe(true)
  })

  it("removes the flash class after the 2s timeout", async () => {
    buildScaffold()
    const target = addTargetEvent(7)
    const { cell } = addHitRow(7)
    vi.spyOn(target, "scrollIntoView")

    await tick()

    vi.useFakeTimers()
    click(cell)
    expect(target.classList.contains("pito-anchor-flash")).toBe(true)

    vi.advanceTimersByTime(1999)
    expect(target.classList.contains("pito-anchor-flash")).toBe(true)

    vi.advanceTimersByTime(1)
    expect(target.classList.contains("pito-anchor-flash")).toBe(false)
  })

  it("cleans up two flashes on different targets independently (no stuck class)", async () => {
    buildScaffold()
    const targetA = addTargetEvent(1)
    const targetB = addTargetEvent(2)
    const { cell: cellA } = addHitRow(1)
    const { cell: cellB } = addHitRow(2)
    vi.spyOn(targetA, "scrollIntoView")
    vi.spyOn(targetB, "scrollIntoView")

    await tick()

    vi.useFakeTimers()
    click(cellA)
    expect(targetA.classList.contains("pito-anchor-flash")).toBe(true)

    // Halfway through A's flash, jump to a different target.
    vi.advanceTimersByTime(1000)
    click(cellB)
    expect(targetB.classList.contains("pito-anchor-flash")).toBe(true)
    expect(targetA.classList.contains("pito-anchor-flash")).toBe(true) // still live

    // A reaches its own 2000ms mark; B has only had 1000ms.
    vi.advanceTimersByTime(1000)
    expect(targetA.classList.contains("pito-anchor-flash")).toBe(false)
    expect(targetB.classList.contains("pito-anchor-flash")).toBe(true) // not stuck, just not due yet

    // B reaches its own 2000ms mark.
    vi.advanceTimersByTime(1000)
    expect(targetB.classList.contains("pito-anchor-flash")).toBe(false)
  })

  it("no-ops without crashing when the event id has no matching element in this DOM", async () => {
    buildScaffold()
    const { cell } = addHitRow(999) // cross-conversation hit — no #event_999 here
    const scrollSpy = vi.spyOn(Element.prototype, "scrollIntoView")

    await tick()

    expect(() => click(cell)).not.toThrow()
    expect(scrollSpy).not.toHaveBeenCalled()

    // The delegated listener must still be alive for a subsequent, valid click.
    const target = addTargetEvent(5)
    const { cell: validCell } = addHitRow(5)
    click(validCell)

    expect(scrollSpy).toHaveBeenCalledTimes(1)
    expect(target.classList.contains("pito-anchor-flash")).toBe(true)
  })

  it("does nothing when the click lands outside any hit row", async () => {
    buildScaffold()
    addTargetEvent(3) // present in the DOM, but nothing references it
    const scrollSpy = vi.spyOn(Element.prototype, "scrollIntoView")

    await tick()

    const plain = document.createElement("div")
    document.body.appendChild(plain)
    click(plain)

    expect(scrollSpy).not.toHaveBeenCalled()
  })
})
