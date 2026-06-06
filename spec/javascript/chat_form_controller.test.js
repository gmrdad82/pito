// spec/javascript/chat_form_controller.test.js
//
// Vitest suite for pito--chat-form Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as history_controller.test.js.
//
// Auth gate: inject #pito-auth-gate[data-authenticated] directly into the DOM.
//
// COVERAGE
//   - Enter submits form + clears field + dispatches `pito:submitted` (non-empty)
//   - Enter on empty field: submits but does NOT dispatch pito:submitted
//   - Shift+Enter: no-op (does not submit)
//   - Shift+Tab cycles channels (updates hidden input + display)
//   - Shift+Space cycles periods (authenticated only)
//   - cable-offline (body[data-pito-cable-offline="true"]) → reloads instead of submitting
//   - handleKeydown returns early (no cycle) when unauthenticated
//
// SKIPPED (jsdom limitations):
//   - requestSubmit form submission actually sending a request (no network in jsdom)

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ChatFormController from "controllers/pito/chat_form_controller"

// ── Auth helpers ─────────────────────────────────────────────────────────────

function setAuthenticated(value) {
  let gate = document.getElementById("pito-auth-gate")
  if (!gate) {
    gate = document.createElement("div")
    gate.id = "pito-auth-gate"
    document.body.appendChild(gate)
  }
  gate.dataset.authenticated = value ? "true" : "false"
}

// ── Scaffold builder ──────────────────────────────────────────────────────────

function buildScaffold({
  channels = ["@all", "@gaming"],
  periods  = ["7d", "28d"],
  authenticated = true
} = {}) {
  setAuthenticated(authenticated)

  const form = document.createElement("form")
  form.className = "chatbox-form"
  form.setAttribute("data-controller", "pito--chat-form")
  form.setAttribute("data-pito--chat-form-channels-value", JSON.stringify(channels))
  form.setAttribute("data-pito--chat-form-periods-value",  JSON.stringify(periods))

  // Prevent default form submission in jsdom
  form.addEventListener("submit", (e) => e.preventDefault())

  const inputField = document.createElement("textarea")
  inputField.setAttribute("data-pito--chat-form-target", "inputField")
  // Wire the action so Stimulus routes keydown events to handleKeydown
  inputField.setAttribute("data-action", "keydown->pito--chat-form#handleKeydown")
  form.appendChild(inputField)

  const hiddenInput = document.createElement("input")
  hiddenInput.type = "hidden"
  hiddenInput.setAttribute("data-pito--chat-form-target", "hiddenInput")
  form.appendChild(hiddenInput)

  // Channel display
  const channelDisplay = document.createElement("span")
  channelDisplay.setAttribute("data-pito--chat-form-target", "channelDisplay")
  const channelCyan = document.createElement("span")
  channelCyan.className = "text-cyan"
  channelCyan.textContent = channels[0] || ""
  channelDisplay.appendChild(channelCyan)
  form.appendChild(channelDisplay)

  // Period display
  const periodDisplay = document.createElement("span")
  periodDisplay.setAttribute("data-pito--chat-form-target", "periodDisplay")
  const periodCyan = document.createElement("span")
  periodCyan.className = "text-cyan"
  periodCyan.textContent = periods[0] || ""
  periodDisplay.appendChild(periodCyan)
  form.appendChild(periodDisplay)

  // Hidden channel input
  const channelInput = document.createElement("input")
  channelInput.type = "hidden"
  channelInput.value = channels[0] || ""
  channelInput.setAttribute("data-pito--chat-form-target", "channelInput")
  form.appendChild(channelInput)

  // Hidden period input
  const periodInput = document.createElement("input")
  periodInput.type = "hidden"
  periodInput.value = periods[0] || ""
  periodInput.setAttribute("data-pito--chat-form-target", "periodInput")
  form.appendChild(periodInput)

  document.body.appendChild(form)

  return { form, inputField, hiddenInput, channelDisplay, periodDisplay, channelInput, periodInput }
}

function keydown(el, key, opts = {}) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, ...opts }))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--chat-form controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--chat-form", ChatFormController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    await app.stop()
    await new Promise((r) => setTimeout(r, 0))
    document.body.innerHTML = ""
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // ── Enter submits and clears ──────────────────────────────────────────────────

  it("Enter submits the form and clears the input field", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()

    inputField.value = "list videos"

    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    keydown(inputField, "Enter")

    expect(inputField.value).toBe("")
    expect(submitted).toBeGreaterThan(0)
  })

  it("Enter dispatches pito:submitted when field is non-empty", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    inputField.value = "list videos"

    const submittedEvents = []
    document.addEventListener("pito:submitted", () => submittedEvents.push(true))

    keydown(inputField, "Enter")

    expect(submittedEvents.length).toBeGreaterThan(0)
    document.removeEventListener("pito:submitted", () => {})
  })

  it("Enter does NOT dispatch pito:submitted when field is empty", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    inputField.value = ""

    const submittedEvents = []
    document.addEventListener("pito:submitted", () => submittedEvents.push(true))

    keydown(inputField, "Enter")

    expect(submittedEvents.length).toBe(0)
    document.removeEventListener("pito:submitted", () => {})
  })

  it("Enter does NOT dispatch pito:submitted when field is whitespace-only", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    inputField.value = "   "

    const submittedEvents = []
    document.addEventListener("pito:submitted", () => submittedEvents.push(true))

    keydown(inputField, "Enter")

    expect(submittedEvents.length).toBe(0)
    document.removeEventListener("pito:submitted", () => {})
  })

  // ── Shift+Enter is a no-op ────────────────────────────────────────────────────

  it("Shift+Enter does not submit the form", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()

    inputField.value = "some text"

    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    keydown(inputField, "Enter", { shiftKey: true })

    expect(submitted).toBe(0)
    expect(inputField.value).toBe("some text") // unchanged
  })

  // ── Shift+Tab cycles channels ─────────────────────────────────────────────────

  it("Shift+Tab cycles to the next channel", async () => {
    const { inputField, channelInput, channelDisplay } = buildScaffold({
      channels: ["@all", "@gaming", "@music"]
    })
    await waitForConnect()

    keydown(inputField, "Tab", { shiftKey: true })

    expect(channelInput.value).toBe("@gaming")
    expect(channelDisplay.querySelector(".text-cyan").textContent).toBe("@gaming")
  })

  it("Shift+Tab wraps around to the first channel", async () => {
    const { inputField, channelInput } = buildScaffold({
      channels: ["@all", "@gaming"]
    })
    await waitForConnect()

    keydown(inputField, "Tab", { shiftKey: true }) // → @gaming
    keydown(inputField, "Tab", { shiftKey: true }) // → @all (wraps)

    expect(channelInput.value).toBe("@all")
  })

  it("plain Tab does not cycle channels", async () => {
    const { inputField, channelInput } = buildScaffold({
      channels: ["@all", "@gaming"]
    })
    await waitForConnect()

    keydown(inputField, "Tab") // plain Tab — reserved for autocomplete

    expect(channelInput.value).toBe("@all") // unchanged
  })

  // ── Shift+Space cycles periods ────────────────────────────────────────────────

  it("Shift+Space cycles to the next period (authenticated)", async () => {
    const { inputField, periodInput, periodDisplay } = buildScaffold({
      periods: ["7d", "28d", "1m"]
    })
    await waitForConnect()

    keydown(inputField, " ", { shiftKey: true, code: "Space" })

    expect(periodInput.value).toBe("28d")
    expect(periodDisplay.querySelector(".text-cyan").textContent).toBe("28d")
  })

  it("Shift+Space does not cycle when unauthenticated", async () => {
    const { inputField, periodInput } = buildScaffold({
      authenticated: false,
      periods: ["7d", "28d"]
    })
    await waitForConnect()

    keydown(inputField, " ", { shiftKey: true, code: "Space" })

    expect(periodInput.value).toBe("7d") // unchanged
  })

  // ── Cable-offline path ────────────────────────────────────────────────────────

  it("Enter reloads the page when cable is offline instead of submitting", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()

    document.body.dataset.pitoCableOffline = "true"

    const reloadMock = vi.fn()
    Object.defineProperty(window, "location", {
      writable: true,
      configurable: true,
      value: { reload: reloadMock },
    })

    inputField.value = "some text"

    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    keydown(inputField, "Enter")

    expect(reloadMock).toHaveBeenCalledOnce()
    expect(submitted).toBe(0)

    delete document.body.dataset.pitoCableOffline
  })

  it("Enter does not reload when cable is online", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()

    const reloadMock = vi.fn()
    Object.defineProperty(window, "location", {
      writable: true,
      configurable: true,
      value: { reload: reloadMock },
    })

    inputField.value = "list videos"
    keydown(inputField, "Enter")

    expect(reloadMock).not.toHaveBeenCalled()
  })

  // ── Unauthenticated: handleKeydown returns early ──────────────────────────────

  it("returns early without cycling when unauthenticated", async () => {
    const { inputField, channelInput } = buildScaffold({
      authenticated: false,
      channels: ["@all", "@gaming"]
    })
    await waitForConnect()

    keydown(inputField, "Tab", { shiftKey: true })

    expect(channelInput.value).toBe("@all") // not cycled
  })

  // ── fillAndSubmit (T10.9) ─────────────────────────────────────────────────────

  describe("fillAndSubmit", () => {
    it("sets the textarea value to the given command and submits", async () => {
      const { form, inputField } = buildScaffold()
      await waitForConnect()

      let submitted = 0
      form.addEventListener("submit", () => submitted++)

      document.dispatchEvent(new CustomEvent("pito:picker:select", {
        detail: { command: "show game #7" }
      }))

      expect(submitted).toBeGreaterThan(0)
    })

    it("clears the textarea after submitting", async () => {
      const { form, inputField } = buildScaffold()
      await waitForConnect()
      form.addEventListener("submit", (e) => e.preventDefault())

      document.dispatchEvent(new CustomEvent("pito:picker:select", {
        detail: { command: "show game #7" }
      }))

      expect(inputField.value).toBe("")
    })

    it("dispatches pito:submitted after submitting", async () => {
      const { form } = buildScaffold()
      await waitForConnect()
      form.addEventListener("submit", (e) => e.preventDefault())

      const submitted = []
      document.addEventListener("pito:submitted", () => submitted.push(true))

      document.dispatchEvent(new CustomEvent("pito:picker:select", {
        detail: { command: "show game #7" }
      }))

      expect(submitted.length).toBeGreaterThan(0)
      document.removeEventListener("pito:submitted", () => {})
    })

    it("is a no-op when event has no command", async () => {
      const { form } = buildScaffold()
      await waitForConnect()
      let submitted = 0
      form.addEventListener("submit", () => submitted++)

      document.dispatchEvent(new CustomEvent("pito:picker:select", {
        detail: {}
      }))

      expect(submitted).toBe(0)
    })
  })
})
