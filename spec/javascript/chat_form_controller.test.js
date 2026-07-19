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
//   - a stale body[data-pito-cable-offline] flag does NOT block submit (no reload, no lost message)
//   - handleKeydown returns early (no cycle) when unauthenticated
//   - Shift+U at caret 0 clicks the LAST [data-pito-use-widget-fill] in the scrollback
//   - Shift+U guards mirror Shift+R (Ctrl+Shift+U passthrough, no-op when none, global listener)
//   - `#<handle> apply|use|accept` fast-path clicks that message's fill widget and
//     blocks submit; absent handle/widget or trailing text falls through to a normal
//     submit (server-side fallback handles it)
//
// SKIPPED (jsdom limitations):
//   - requestSubmit form submission actually sending a request (no network in jsdom)

import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from "vitest"
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
  // ONE long-lived Stimulus application for the whole file. Re-calling
  // Application.start() per test and stopping it did NOT reliably disconnect the
  // controllers, so their global document `keydown`/picker listeners accumulated
  // across tests (one Shift+R then fired ~18 leaked controllers → "expected 18 to
  // be 1"). With a single persistent app, clearing the DOM in afterEach lets the
  // live observer fire disconnect() on the removed controller, removing its
  // listeners — exactly one controller is ever connected at a time.
  let app

  beforeAll(() => {
    app = Application.start()
    app.register("pito--chat-form", ChatFormController)
  })

  afterAll(async () => {
    await app.stop()
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    // Clear the DOM so the live app disconnects the removed controller (firing
    // removeEventListener on its global keydown/picker listeners) before the next
    // test connects a fresh one.
    document.body.innerHTML = ""
    await new Promise((r) => setTimeout(r, 0))
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
      periods: ["7d", "28d", "3m"]
    })
    await waitForConnect()

    keydown(inputField, " ", { shiftKey: true, code: "Space" })

    expect(periodInput.value).toBe("28d")
    expect(periodDisplay.querySelector(".text-cyan").textContent).toBe("28d")
  })

  // ── item 10: cycling + sending gated on hint visibility ───────────────────────

  it("Shift+Tab does NOT cycle the channel when its hint is hidden", async () => {
    const { inputField, channelInput, channelDisplay } = buildScaffold({
      channels: ["@all", "@gaming"]
    })
    await waitForConnect()
    channelDisplay.classList.add("hidden") // not `list vids/games`

    keydown(inputField, "Tab", { shiftKey: true })

    expect(channelInput.value).toBe("@all") // unchanged
  })

  it("Shift+Space does NOT cycle the period when its hint is hidden", async () => {
    const { inputField, periodInput, periodDisplay } = buildScaffold({
      periods: ["7d", "28d"]
    })
    await waitForConnect()
    periodDisplay.classList.add("hidden") // not `analyze`

    keydown(inputField, " ", { shiftKey: true, code: "Space" })

    expect(periodInput.value).toBe("7d") // unchanged
  })

  it("on submit, channelInput is DISABLED (omitted) when its hint is hidden", async () => {
    const { inputField, channelInput, channelDisplay, periodInput, periodDisplay } = buildScaffold()
    await waitForConnect()
    channelDisplay.classList.add("hidden")
    periodDisplay.classList.add("hidden")
    inputField.value = "show game 5"

    keydown(inputField, "Enter")

    expect(channelInput.disabled).toBe(true)
    expect(periodInput.disabled).toBe(true)
  })

  it("on submit, channelInput stays ENABLED (sent) when its hint is visible", async () => {
    const { inputField, channelInput, channelDisplay } = buildScaffold()
    await waitForConnect()
    channelDisplay.classList.remove("hidden") // visible (`list vids/games`)
    inputField.value = "list vids"

    keydown(inputField, "Enter")

    expect(channelInput.disabled).toBe(false)
  })

  it("default periods value does not include '1m' and contains exactly 5 tokens", async () => {
    // Mount without an explicit periods override so the Stimulus default kicks in.
    setAuthenticated(true)
    const form = document.createElement("form")
    form.setAttribute("data-controller", "pito--chat-form")
    form.addEventListener("submit", (e) => e.preventDefault())
    const inputField = document.createElement("textarea")
    inputField.setAttribute("data-pito--chat-form-target", "inputField")
    form.appendChild(inputField)
    const hiddenInput = document.createElement("input")
    hiddenInput.type = "hidden"
    hiddenInput.setAttribute("data-pito--chat-form-target", "hiddenInput")
    form.appendChild(hiddenInput)
    document.body.appendChild(form)
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(form, "pito--chat-form")
    expect(ctrl.periodsValue).not.toContain("1m")
    expect(ctrl.periodsValue).toHaveLength(5)
    expect(ctrl.periodsValue).toEqual(["7d", "28d", "3m", "1y", "lifetime"])
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

  it("Enter submits and never reloads even with a stale cable-offline flag — message is not lost", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()

    // A leftover flag must NOT block submission: the message POSTs over HTTP,
    // independent of the WebSocket. (The old reload-here path silently ate it.)
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

    expect(reloadMock).not.toHaveBeenCalled()
    expect(submitted).toBeGreaterThan(0)
    expect(inputField.value).toBe("")

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

  // ── Shift+R reply prefix vs. Ctrl+Shift+R browser reload ──────────────────────

  it("Shift+R at caret 0 prepends the last hashtag handle", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    const marker = document.createElement("span")
    marker.dataset.pitoHandle = "kappa-5874"
    document.body.appendChild(marker)

    inputField.value = ""
    inputField.focus() // box focused → the global shift+r listener defers to the textarea action (no double-fire)
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "R", { shiftKey: true, code: "KeyR" })

    expect(inputField.value).toBe("#kappa-5874 ")
    marker.remove()
  })

  it("Ctrl+Shift+R does NOT prepend (browser hard-reload passes through)", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    const marker = document.createElement("span")
    marker.dataset.pitoHandle = "kappa-5874"
    document.body.appendChild(marker)

    inputField.value = ""
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "R", { shiftKey: true, ctrlKey: true, code: "KeyR" })

    expect(inputField.value).toBe("")
    marker.remove()
  })

  // ── Shift+R hashtag picker (P18) ──────────────────────────────────────────────

  // Build a scrollback turn carrying `handles` as live `[data-pito-handle]`
  // tokens (the only thing left in the DOM once a follow-up is consumed).
  function buildTurnWithHandles(handles, { id = "1" } = {}) {
    const scrollback = document.createElement("div")
    scrollback.id = "pito-scrollback"
    const turn = document.createElement("div")
    turn.className = "pito-turn"
    turn.id = `turn_${id}`
    handles.forEach((h) => {
      const span = document.createElement("span")
      span.dataset.pitoHandle = h
      turn.appendChild(span)
    })
    scrollback.appendChild(turn)
    document.body.appendChild(scrollback)
    return scrollback
  }

  it("Shift+R with one live handle prepends it directly (no picker)", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const scrollback = buildTurnWithHandles(["kappa-5874"])

    const pickerEvents = []
    document.addEventListener("pito:hashtag-picker:open", (e) => pickerEvents.push(e))

    inputField.value = ""
    inputField.focus() // box focused → global shift+r listener defers to the textarea action
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "R", { shiftKey: true, code: "KeyR" })

    expect(inputField.value).toBe("#kappa-5874 ")
    expect(pickerEvents.length).toBe(0)
    scrollback.remove()
  })

  it("Shift+R with more than one live handle opens the picker (does not prefill)", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const scrollback = buildTurnWithHandles(["kappa-5874", "doomguy-21", "lima-09"])

    const pickerEvents = []
    document.addEventListener("pito:hashtag-picker:open", (e) => pickerEvents.push(e))

    inputField.value = ""
    inputField.focus() // box focused → global shift+r listener defers to the textarea action
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "R", { shiftKey: true, code: "KeyR" })

    expect(pickerEvents.length).toBe(1)
    expect(pickerEvents[0].detail.handles).toEqual(["kappa-5874", "doomguy-21", "lima-09"])
    // The chatbox is left untouched — the user picks, then types the action.
    expect(inputField.value).toBe("")
    scrollback.remove()
  })

  it("Shift+R only collects handles from the LAST handle-bearing turn", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    // Two turns: an older one and the most recent multi-handle command.
    const scrollback = document.createElement("div")
    scrollback.id = "pito-scrollback"
    const older = document.createElement("div")
    older.className = "pito-turn"
    const oldSpan = document.createElement("span")
    oldSpan.dataset.pitoHandle = "old-handle"
    older.appendChild(oldSpan)
    const recent = document.createElement("div")
    recent.className = "pito-turn"
    ;["alpha-1", "bravo-2"].forEach((h) => {
      const s = document.createElement("span")
      s.dataset.pitoHandle = h
      recent.appendChild(s)
    })
    scrollback.appendChild(older)
    scrollback.appendChild(recent)
    document.body.appendChild(scrollback)

    const pickerEvents = []
    document.addEventListener("pito:hashtag-picker:open", (e) => pickerEvents.push(e))

    inputField.value = ""
    inputField.focus() // box focused → global shift+r listener defers to the textarea action
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "R", { shiftKey: true, code: "KeyR" })

    expect(pickerEvents.length).toBe(1)
    expect(pickerEvents[0].detail.handles).toEqual(["alpha-1", "bravo-2"])
    scrollback.remove()
  })

  it("Shift+R is a no-op when there are zero live handles", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    const pickerEvents = []
    document.addEventListener("pito:hashtag-picker:open", (e) => pickerEvents.push(e))

    inputField.value = ""
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "R", { shiftKey: true, code: "KeyR" })

    expect(inputField.value).toBe("")
    expect(pickerEvents.length).toBe(0)
  })

  // ── Shift+U stages the latest use-widget vs. Ctrl+Shift+U guard ──────────────

  // Build a scrollback carrying `count` shift+u accept chips
  // (Pito::Event::Ai::SuggestionBlockComponent's chip — a <span>, mirroring
  // the real markup) — the only thing #stageLatestSuggestion looks for, so a
  // bare span with the marker attribute is enough.
  function buildScrollbackWithFillButtons(count) {
    const scrollback = document.createElement("div")
    scrollback.id = "pito-scrollback"
    const buttons = []
    for (let i = 0; i < count; i++) {
      const chip = document.createElement("span")
      chip.setAttribute("data-pito-use-widget-fill", "")
      scrollback.appendChild(chip)
      buttons.push(chip)
    }
    document.body.appendChild(scrollback)
    return { scrollback, buttons }
  }

  it("Shift+U at caret 0 clicks the LAST use-widget fill button when several are rendered", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, buttons } = buildScrollbackWithFillButtons(2)

    const clicks = []
    buttons[0].addEventListener("click", () => clicks.push("first"))
    buttons[1].addEventListener("click", () => clicks.push("second"))

    inputField.value = ""
    inputField.focus() // box focused → the global listener defers to the textarea action (no double-fire)
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "U", { shiftKey: true, code: "KeyU" })

    expect(clicks).toEqual(["second"])
    scrollback.remove()
  })

  it("Shift+U is a no-op when no use-widget fill button is rendered", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()

    inputField.value = ""
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "U", { shiftKey: true, code: "KeyU" })

    expect(inputField.value).toBe("") // unchanged — nothing to stage
  })

  it("Shift+U mid-line (caret not at 0) does NOT click the widget", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, buttons } = buildScrollbackWithFillButtons(1)

    let clicked = 0
    buttons[0].addEventListener("click", () => clicked++)

    inputField.value = "hello"
    inputField.focus()
    inputField.selectionStart = inputField.selectionEnd = 3
    keydown(inputField, "U", { shiftKey: true, code: "KeyU" })

    expect(clicked).toBe(0)
    scrollback.remove()
  })

  it("Ctrl+Shift+U does NOT stage (mirrors Shift+R's modifier guard)", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, buttons } = buildScrollbackWithFillButtons(1)

    let clicked = 0
    buttons[0].addEventListener("click", () => clicked++)

    inputField.value = ""
    inputField.focus()
    inputField.selectionStart = inputField.selectionEnd = 0
    keydown(inputField, "U", { shiftKey: true, ctrlKey: true, code: "KeyU" })

    expect(clicked).toBe(0)
    scrollback.remove()
  })

  it("Shift+U fires globally even when the chatbox is not focused", async () => {
    buildScaffold()
    await waitForConnect()
    const { scrollback, buttons } = buildScrollbackWithFillButtons(1)

    let clicked = 0
    buttons[0].addEventListener("click", () => clicked++)

    // Nothing editable is focused (activeElement defaults to <body>), so the
    // global document listener — not the textarea's own keydown action —
    // must be the one that handles this.
    keydown(document, "U", { shiftKey: true, code: "KeyU" })

    expect(clicked).toBe(1)
    scrollback.remove()
  })

  it("Shift+U global listener does NOT hijack typing in another editable element", async () => {
    buildScaffold()
    await waitForConnect()
    const { scrollback, buttons } = buildScrollbackWithFillButtons(1)

    const otherInput = document.createElement("input")
    document.body.appendChild(otherInput)
    otherInput.focus()

    let clicked = 0
    buttons[0].addEventListener("click", () => clicked++)

    keydown(otherInput, "U", { shiftKey: true, code: "KeyU" })

    expect(clicked).toBe(0)
    scrollback.remove()
    otherInput.remove()
  })

  // ── `#<handle> apply|use|accept` fast-path (WP6) ──────────────────────────────

  // Build a `.pito-segment` message container carrying a `data-pito-handle`
  // token and (optionally) a shift+u accept chip as SIBLINGS — mirroring the
  // real AiComponent markup, where MetaLineComponent's #handle and the
  // SuggestionBlockComponent's chip are both descendants of the SAME
  // Pito::Segment::Component root (id="event_<id>", class="pito-segment").
  function buildAiMessageSegment(handle, { withWidget = true } = {}) {
    const scrollback = document.createElement("div")
    scrollback.id = "pito-scrollback"

    const segment = document.createElement("div")
    segment.className = "pito-segment"

    const handleSpan = document.createElement("span")
    handleSpan.dataset.pitoHandle = handle
    segment.appendChild(handleSpan)

    let widget = null
    if (withWidget) {
      widget = document.createElement("span")
      widget.setAttribute("data-pito-use-widget-fill", "")
      segment.appendChild(widget)
    }

    scrollback.appendChild(segment)
    document.body.appendChild(scrollback)
    return { scrollback, segment, widget }
  }

  it.each(["apply", "use", "accept"])("Enter on '#h1 %s' clicks the fill widget and does NOT submit", async (action) => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, widget } = buildAiMessageSegment("h1")

    let clicked = 0
    widget.addEventListener("click", () => clicked++)
    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    inputField.value = `#h1 ${action}`
    keydown(inputField, "Enter")

    expect(clicked).toBe(1)
    expect(submitted).toBe(0)
    scrollback.remove()
  })

  it("is case-insensitive on both the handle and the action word", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, widget } = buildAiMessageSegment("kappa-5874")

    let clicked = 0
    widget.addEventListener("click", () => clicked++)

    inputField.value = "#KAPPA-5874 APPLY"
    keydown(inputField, "Enter")

    expect(clicked).toBe(1)
    scrollback.remove()
  })

  it("falls through to a normal submit when the handle isn't found", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, widget } = buildAiMessageSegment("h1")

    let clicked = 0
    widget.addEventListener("click", () => clicked++)
    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    inputField.value = "#nope-0000 apply"
    keydown(inputField, "Enter")

    expect(clicked).toBe(0)
    expect(submitted).toBeGreaterThan(0)
    scrollback.remove()
  })

  it("falls through to a normal submit when the message has no fill widget (server fallback handles it)", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback } = buildAiMessageSegment("h1", { withWidget: false })

    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    inputField.value = "#h1 apply"
    keydown(inputField, "Enter")

    expect(submitted).toBeGreaterThan(0)
    expect(inputField.value).toBe("") // the normal Enter path clears the field
    scrollback.remove()
  })

  it("falls through to a normal submit when trailing text follows the action word", async () => {
    const { form, inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback, widget } = buildAiMessageSegment("h1")

    let clicked = 0
    widget.addEventListener("click", () => clicked++)
    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    inputField.value = "#h1 apply now"
    keydown(inputField, "Enter")

    expect(clicked).toBe(0)
    expect(submitted).toBeGreaterThan(0)
    scrollback.remove()
  })

  it("does not click a fill widget belonging to a DIFFERENT message", async () => {
    const { inputField } = buildScaffold()
    await waitForConnect()
    const { scrollback: sb1, widget: widget1 } = buildAiMessageSegment("h1")
    const { scrollback: sb2 } = buildAiMessageSegment("h2", { withWidget: false })
    // Merge both segments under one scrollback (buildAiMessageSegment makes its
    // own #pito-scrollback each call — collapse to a single one, as the real DOM
    // only ever has one).
    while (sb2.firstChild) sb1.appendChild(sb2.firstChild)
    sb2.remove()

    let clicked = 0
    widget1.addEventListener("click", () => clicked++)

    inputField.value = "#h2 apply"
    keydown(inputField, "Enter")

    expect(clicked).toBe(0) // h2's segment has no widget of its own
    sb1.remove()
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

  it("Enter STILL submits when unauthenticated (so /login can be sent)", async () => {
    const { form, inputField } = buildScaffold({ authenticated: false })
    await waitForConnect()

    inputField.value = "/login 558183"

    let submitted = 0
    form.addEventListener("submit", () => submitted++)

    keydown(inputField, "Enter")

    expect(submitted).toBeGreaterThan(0)
    expect(inputField.value).toBe("")
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
