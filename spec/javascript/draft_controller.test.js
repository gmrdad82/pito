// spec/javascript/draft_controller.test.js
//
// Vitest suite for pito--draft Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as history_controller.test.js.
// Uses Vitest fake timers to control the 800ms debounce.
//
// COVERAGE
//   - debounced PATCH on input (waits 800ms after last keystroke)
//   - reset timer on rapid input (only latest triggers the PATCH)
//   - skip redundant (same value as last saved)
//   - skip empty→empty on first connect (never saved + empty)
//   - skip bare `/` and `#`
//   - cancel pending debounce on form submit
//   - correct request body `{ draft: <value> }` + CSRF header (mock fetch)
//   - no-op when uuid is blank
//
// SKIPPED: actual network responses are not tested (jsdom, no server)

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import DraftController from "controllers/pito/draft_controller"

// ── Scaffold ──────────────────────────────────────────────────────────────────

const DEBOUNCE_MS = 800

function buildScaffold(uuid = "test-uuid-1234") {
  const chatbox = document.createElement("div")
  chatbox.id = "pito-chatbox"
  chatbox.setAttribute("data-controller", "pito--draft")
  if (uuid) chatbox.setAttribute("data-pito--draft-uuid-value", uuid)

  const form = document.createElement("form")
  form.className = "chatbox-form"
  chatbox.appendChild(form)

  const textarea = document.createElement("textarea")
  form.appendChild(textarea)

  document.body.appendChild(chatbox)

  return { chatbox, form, textarea }
}

// Fire an input event on the textarea
function inputEvent(textarea, value) {
  textarea.value = value
  textarea.dispatchEvent(new Event("input", { bubbles: true }))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--draft controller", () => {
  let app

  beforeEach(() => {
    vi.useFakeTimers()
    app = Application.start()
    app.register("pito--draft", DraftController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    await app.stop()
    // Restore real timers AFTER stopping the app so pending timers don't leak
    vi.useRealTimers()
    await new Promise((r) => setTimeout(r, 0))
    document.body.innerHTML = ""
  })

  async function waitForConnect() {
    // With fake timers, we must advance the clock to process any internal
    // Stimulus connection callbacks that use setTimeout.
    vi.advanceTimersByTime(0)
    await Promise.resolve()
  }

  // ── Debounced PATCH on input ──────────────────────────────────────────────────

  it("fires a PATCH after DEBOUNCE_MS ms of inactivity", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "hello world")

    expect(fetchMock).not.toHaveBeenCalled()

    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve() // flush microtasks

    expect(fetchMock).toHaveBeenCalledOnce()
    expect(fetchMock).toHaveBeenCalledWith(
      "/chat/test-uuid-1234",
      expect.objectContaining({ method: "PATCH" })
    )
  })

  it("sends correct body { draft: <value> }", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "my draft text")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    const body = JSON.parse(fetchMock.mock.calls[0][1].body)
    expect(body).toEqual({ draft: "my draft text" })
  })

  it("includes Content-Type: application/json header", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "typed")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock.mock.calls[0][1].headers["Content-Type"]).toBe("application/json")
  })

  it("includes X-CSRF-Token header when meta tag is present", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "test-csrf-token"
    document.head.appendChild(meta)

    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "with csrf")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("test-csrf-token")

    meta.remove()
  })

  // ── Reset timer on rapid input ────────────────────────────────────────────────

  it("resets the timer on rapid input (only last fires)", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "first")
    vi.advanceTimersByTime(400)
    inputEvent(textarea, "second")
    vi.advanceTimersByTime(400) // total 800ms from first, but timer was reset
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()

    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).toHaveBeenCalledOnce()
    const body = JSON.parse(fetchMock.mock.calls[0][1].body)
    expect(body.draft).toBe("second")
  })

  // ── Skip redundant saves ──────────────────────────────────────────────────────

  it("skips PATCH when value is unchanged since last save", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    // First save
    inputEvent(textarea, "same value")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()
    expect(fetchMock).toHaveBeenCalledOnce()

    // Second input with same value — should skip
    inputEvent(textarea, "same value")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).toHaveBeenCalledOnce() // still 1
  })

  // ── Skip empty→empty on first connect ────────────────────────────────────────

  it("skips PATCH for empty field on first save (empty→empty)", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()
  })

  // ── Skip bare trigger chars ───────────────────────────────────────────────────

  it("skips PATCH for bare '/' input", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "/")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("skips PATCH for bare '#' input", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "#")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("does NOT skip PATCH for '/config ' (more than bare /)", async () => {
    const { textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "/config ")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).toHaveBeenCalledOnce()
  })

  // ── Cancel pending on form submit ─────────────────────────────────────────────

  it("cancels pending PATCH when the form is submitted", async () => {
    const { form, textarea } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "will be cancelled")
    vi.advanceTimersByTime(400) // not yet fired

    form.dispatchEvent(new Event("submit", { bubbles: true }))

    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()
  })

  // ── No-op when uuid is blank ──────────────────────────────────────────────────

  it("does not fire PATCH when uuid is blank", async () => {
    const chatbox = document.createElement("div")
    chatbox.setAttribute("data-controller", "pito--draft")
    // No uuid value attribute → uuidValue will be ""
    const textarea = document.createElement("textarea")
    chatbox.appendChild(textarea)
    document.body.appendChild(chatbox)
    await waitForConnect()

    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)

    inputEvent(textarea, "ignored because no uuid")
    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()
  })

  // ── Only triggers on TEXTAREA input events ────────────────────────────────────

  it("ignores input events from non-TEXTAREA elements", async () => {
    const { chatbox } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 })
    vi.stubGlobal("fetch", fetchMock)

    // Trigger input from a non-textarea element
    const div = document.createElement("div")
    chatbox.appendChild(div)
    div.dispatchEvent(new Event("input", { bubbles: true }))

    vi.advanceTimersByTime(DEBOUNCE_MS)
    await Promise.resolve()

    expect(fetchMock).not.toHaveBeenCalled()
  })
})
