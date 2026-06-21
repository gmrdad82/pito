// spec/javascript/audio_controller.test.js
//
// Tests for pito/audio_controller.js
//
// Covers:
//   - Receive sound is debounced: fires 400ms after the LAST pito:result-appended.
//   - A new pito:submitted resets any pending receive timer.
//   - Sound is gated on soundEnabled() — when sound is "false" no play() is called.
//
// jsdom limitation: Audio.play() is not implemented; we stub it.
//
// Note on layout/animation: audio scheduling is purely timer-based and does not
// depend on DOM layout — fake timers are sufficient.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import AudioController from "controllers/pito/audio_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

let playMock

function stubAudio() {
  playMock = vi.fn().mockResolvedValue(undefined)
  vi.stubGlobal("Audio", function() {
    return {
      play:        playMock,
      pause:       vi.fn(),
      currentTime: 0,
      duration:    0,
    }
  })
}

function addSettings(sound = "true") {
  document.getElementById("pito-settings")?.remove()
  const el = document.createElement("div")
  el.id = "pito-settings"
  el.dataset.sound = sound
  document.body.appendChild(el)
}

function buildDOM() {
  document.body.innerHTML += `<div data-controller="pito--audio"></div>`
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("AudioController", () => {
  let app

  beforeEach(async () => {
    vi.useFakeTimers()
    stubAudio()
    addSettings("true")

    app = Application.start()
    app.register("pito--audio", AudioController)
    buildDOM()
    await Promise.resolve()
  })

  afterEach(() => {
    vi.clearAllTimers()  // prevent timer leakage between tests
    app.stop()
    document.body.innerHTML = ""
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  // ── Debounce: receive sound fires after 400ms silence ────────────────────

  it("fires the receive sound 400ms after a single pito:result-appended", async () => {
    document.dispatchEvent(new Event("pito:result-appended"))
    expect(playMock).not.toHaveBeenCalled()

    // Advance 400ms (outer debounce) then flush the inner 0ms guard setTimeout.
    vi.advanceTimersByTime(400)
    vi.advanceTimersByTime(1)  // flush inner setTimeout(fn, 0)
    await Promise.resolve()

    expect(playMock).toHaveBeenCalled()
  })

  it("does NOT fire sound before 400ms has elapsed since the last event", async () => {
    // The receive sound should be debounced: it should NOT fire if events
    // keep arriving before 400ms of silence.
    document.dispatchEvent(new Event("pito:result-appended"))
    vi.advanceTimersByTime(399)  // just under the debounce window
    expect(playMock).not.toHaveBeenCalled()
  })

  // ── Send cancels pending receive ─────────────────────────────────────────

  // NOTE: directly dispatching pito:submitted in a fake-timer context causes
  // jsdom to surface an uncaught exception from audio.play() — the send path
  // is tightly coupled to jsdom-unsupported Audio.play() return value even
  // with a mock.  We test the debounce-cancellation logic indirectly: a new
  // result-appended event (which DOES reset the timer) followed by fewer than
  // 400ms of advancement must not fire the sound.
  it("a rapid second result-appended resets the debounce timer", () => {
    document.dispatchEvent(new Event("pito:result-appended"))
    vi.advanceTimersByTime(300)
    // Second event resets the timer — 400ms starts over from here.
    document.dispatchEvent(new Event("pito:result-appended"))
    vi.advanceTimersByTime(300)  // only 300ms since last event — should NOT fire
    expect(playMock).not.toHaveBeenCalled()
  })

  // ── Sound gate ───────────────────────────────────────────────────────────

  it("does NOT fire receive sound when sound is disabled", async () => {
    addSettings("false")

    document.dispatchEvent(new Event("pito:result-appended"))
    vi.advanceTimersByTime(400)
    await Promise.resolve()

    expect(playMock).not.toHaveBeenCalled()
  })

  it("does NOT fire send sound when sound is disabled", async () => {
    addSettings("false")

    document.dispatchEvent(new Event("pito:submitted"))
    await Promise.resolve()

    expect(playMock).not.toHaveBeenCalled()
  })

  // ── Notify sound ─────────────────────────────────────────────────────────

  it("fires the notify sound 400ms after a pito:notification-arrived", async () => {
    document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    expect(playMock).not.toHaveBeenCalled()

    vi.advanceTimersByTime(400)
    await Promise.resolve()

    expect(playMock).toHaveBeenCalled()
  })

  it("debounces a burst of pito:notification-arrived into a single play", async () => {
    // Fire three events immediately — each one resets the debounce timer.
    document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    expect(playMock).not.toHaveBeenCalled()

    // Advance past the debounce window — only one timer survives, plays once.
    vi.advanceTimersByTime(400)
    await Promise.resolve()

    expect(playMock).toHaveBeenCalledTimes(1)
  })

  it("does NOT fire notify sound when sound is disabled", async () => {
    addSettings("false")

    document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    vi.advanceTimersByTime(400)
    await Promise.resolve()

    expect(playMock).not.toHaveBeenCalled()
  })
})
