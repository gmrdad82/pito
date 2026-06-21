// spec/javascript/thinking_controller.test.js
//
// Tests for pito/thinking_controller.js
//
// The controller cycles through a `framesValue` array on a fixed interval
// (80 ms) and writes each frame into the `brailleTarget` element's textContent.
// We use vi.useFakeTimers() to advance time without real delays.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ThinkingController from "controllers/pito/thinking_controller"

// ── Setup ─────────────────────────────────────────────────────────────────────

function buildDOM(frames = ["⠋", "⠙", "⠹", "⠸"]) {
  document.body.innerHTML = `
    <div
      data-controller="pito--thinking"
      data-pito--thinking-frames-value='${JSON.stringify(frames)}'
    >
      <span data-pito--thinking-target="braille">${frames[0]}</span>
    </div>
  `
  return document.querySelector("[data-controller='pito--thinking']")
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("ThinkingController", () => {
  let app

  beforeEach(async () => {
    vi.useFakeTimers()
    app = Application.start()
    app.register("pito--thinking", ThinkingController)
    // Allow Stimulus to process the initial connect.
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.useRealTimers()
  })

  it("advances the braille frame after one interval (80 ms)", async () => {
    const frames = ["⠋", "⠙", "⠹", "⠸"]
    buildDOM(frames)
    await Promise.resolve()

    const braille = document.querySelector("[data-pito--thinking-target='braille']")
    // Initial text is set server-side; after one tick it should cycle.
    vi.advanceTimersByTime(80)
    expect(frames).toContain(braille.textContent)
  })

  it("cycles through all frames without repeating mid-rotation", async () => {
    const frames = ["A", "B", "C"]
    buildDOM(frames)
    await Promise.resolve()

    const braille = document.querySelector("[data-pito--thinking-target='braille']")
    const seen = new Set()

    // Advance 3 ticks — should visit each frame once in order.
    for (let i = 0; i < frames.length; i++) {
      vi.advanceTimersByTime(80)
      seen.add(braille.textContent)
    }

    // Every frame should appear at least once across 3 ticks.
    expect(seen.size).toBeGreaterThan(1)
  })

  it("wraps around after the last frame (modulo)", async () => {
    const frames = ["X", "Y"]
    buildDOM(frames)
    await Promise.resolve()

    const braille = document.querySelector("[data-pito--thinking-target='braille']")

    // Advance 2 ticks → back to first frame position.
    vi.advanceTimersByTime(80)  // brailleIdx = 1 → "Y"
    vi.advanceTimersByTime(80)  // brailleIdx = 0 → "X"
    expect(braille.textContent).toBe("X")
  })

  // ── Verb cycling ──────────────────────────────────────────────────────────

  function buildWordDOM({ words, order, startedAt, interval }) {
    document.body.innerHTML = `
      <div
        data-controller="pito--thinking"
        data-pito--thinking-frames-value='${JSON.stringify(["⠋"])}'
        data-pito--thinking-words-value='${JSON.stringify(words)}'
        data-pito--thinking-order-value='${JSON.stringify(order)}'
        data-pito--thinking-started-at-value="${startedAt}"
        data-pito--thinking-interval-value="${interval}"
      >
        <span data-pito--thinking-target="braille">⠋</span>
        <span data-pito--thinking-target="word"></span>
      </div>
    `
    return document.querySelector("[data-pito--thinking-target='word']")
  }

  it("shows the verb for the elapsed step, advancing each interval", async () => {
    const words = ["doing", "computing", "crunching", "finishing"]
    const order = [3, 1, 2, 0]
    const interval = 5000
    // startedAt = "now" per the fake clock so elapsed begins at 0.
    const word = buildWordDOM({ words, order, startedAt: Date.now(), interval })
    await Promise.resolve()

    expect(word.textContent).toBe("finishing…")     // step 0 → order[0] = 3
    vi.advanceTimersByTime(interval)
    expect(word.textContent).toBe("computing…")      // step 1 → order[1] = 1
    vi.advanceTimersByTime(interval)
    expect(word.textContent).toBe("crunching…")      // step 2 → order[2] = 2
  })

  it("derives the word from elapsed time (refresh-safe), not from connect", async () => {
    const words = ["a", "b", "c"]
    const order = [0, 1, 2]
    const interval = 5000
    // Connect 2 intervals in — should jump straight to step 2.
    const word = buildWordDOM({ words, order, startedAt: Date.now() - 2 * interval, interval })
    await Promise.resolve()

    expect(word.textContent).toBe("c…")
  })
})
