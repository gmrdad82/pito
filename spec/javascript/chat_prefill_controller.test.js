// spec/javascript/chat_prefill_controller.test.js
//
// Tests for pito/chat_prefill_controller.js
//
// Clicking a click-to-type token prefills the chatbox textarea with a fixed
// string, focuses it, moves the caret to the end, and fires `input` — WITHOUT
// submitting any form.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ChatPrefillController from "controllers/pito/chat_prefill_controller"
import ChatFormController from "controllers/pito/chat_form_controller"

function build(text, { submit = false } = {}) {
  const submitAttr = submit ? `data-pito--chat-prefill-submit-value="true"` : ""
  document.body.innerHTML = `
    <form id="chat-form">
      <textarea data-pito--chat-form-target="inputField"></textarea>
    </form>
    <span
      data-controller="pito--chat-prefill"
      data-action="click->pito--chat-prefill#fill"
      data-pito--chat-prefill-text-value="${text}"
      ${submitAttr}
    >token</span>
  `
  return document.querySelector("span[data-controller='pito--chat-prefill']")
}

describe("ChatPrefillController", () => {
  let app

  beforeEach(async () => {
    app = Application.start()
    app.register("pito--chat-prefill", ChatPrefillController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("sets the chatbox value, focuses it, and puts the caret at the end", async () => {
    const token = build("show video #42")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')

    token.click()

    expect(field.value).toBe("show video #42")
    expect(document.activeElement).toBe(field)
    expect(field.selectionStart).toBe(field.value.length)
    expect(field.selectionEnd).toBe(field.value.length)
  })

  it("fires an input event so suggestions/ghost react", async () => {
    const token = build("show game #7")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const onInput = vi.fn()
    field.addEventListener("input", onInput)

    token.click()

    expect(onInput).toHaveBeenCalledTimes(1)
  })

  it("never submits the form when submit is not set (reply #hashtag prefill-only)", async () => {
    const token = build("#alpha-42 ")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const form = document.getElementById("chat-form")
    const onSubmit = vi.fn((e) => e.preventDefault())
    const onKeydown = vi.fn()
    form.addEventListener("submit", onSubmit)
    field.addEventListener("keydown", onKeydown)

    token.click()

    expect(onSubmit).not.toHaveBeenCalled()
    // No synthetic Enter is dispatched, so prefill-only behaviour is preserved.
    expect(onKeydown).not.toHaveBeenCalled()
    expect(field.value).toBe("#alpha-42 ")
  })

  it("dispatches a synthetic Enter keydown on the field when submit:true", async () => {
    const token = build("show vid #42", { submit: true })
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const keys = []
    field.addEventListener("keydown", (e) => keys.push(e.key))

    token.click()

    expect(keys).toContain("Enter")
  })

  it("is a no-op when the chatbox is absent", async () => {
    document.body.innerHTML = `
      <span
        data-controller="pito--chat-prefill"
        data-action="click->pito--chat-prefill#fill"
        data-pito--chat-prefill-text-value="show game #1"
      >token</span>
    `
    await Promise.resolve()

    expect(() => {
      document.querySelector("span[data-controller='pito--chat-prefill']").click()
    }).not.toThrow()
  })
})

// Integration: with the real pito--chat-form controller mounted alongside, a
// submit:true #id click reuses chat-form's Enter handler end-to-end — the form
// submits, the field clears, and pito:submitted fires (a real Enter). A
// submit:false reply #hashtag click does none of that.
describe("ChatPrefillController + chat-form (auto-submit reuse)", () => {
  let app

  function buildScaffold(text, { submit = false } = {}) {
    const gate = document.createElement("div")
    gate.id = "pito-auth-gate"
    gate.dataset.authenticated = "true"
    document.body.appendChild(gate)

    const submitAttr = submit ? `data-pito--chat-prefill-submit-value="true"` : ""
    const wrap = document.createElement("div")
    wrap.innerHTML = `
      <form data-controller="pito--chat-form">
        <textarea
          data-pito--chat-form-target="inputField"
          data-action="keydown->pito--chat-form#handleKeydown"></textarea>
        <input type="hidden" data-pito--chat-form-target="hiddenInput">
      </form>
      <span
        data-controller="pito--chat-prefill"
        data-action="click->pito--chat-prefill#fill"
        data-pito--chat-prefill-text-value="${text}"
        ${submitAttr}
      >token</span>
    `
    document.body.appendChild(wrap)
    // jsdom never performs a real navigation on submit.
    document.querySelector("form").addEventListener("submit", (e) => e.preventDefault())
    return document.querySelector("span[data-controller='pito--chat-prefill']")
  }

  beforeEach(() => {
    app = Application.start()
    app.register("pito--chat-prefill", ChatPrefillController)
    app.register("pito--chat-form", ChatFormController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  const tick = () => new Promise((r) => setTimeout(r, 0))

  it("submit:true #id click submits the form, clears the field, and fires pito:submitted", async () => {
    const token = buildScaffold("show vid #42", { submit: true })
    await tick()

    const form = document.querySelector("form")
    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    let submitted = 0
    const submittedEvents = []
    form.addEventListener("submit", () => submitted++)
    document.addEventListener("pito:submitted", () => submittedEvents.push(true))

    token.click()

    expect(submitted).toBeGreaterThan(0)
    expect(submittedEvents.length).toBeGreaterThan(0)
    expect(field.value).toBe("")
  })

  it("submit:false reply #hashtag click does NOT submit or fire pito:submitted", async () => {
    const token = buildScaffold("#alpha-42 ")
    await tick()

    const form = document.querySelector("form")
    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    let submitted = 0
    const submittedEvents = []
    form.addEventListener("submit", () => submitted++)
    document.addEventListener("pito:submitted", () => submittedEvents.push(true))

    token.click()

    expect(submitted).toBe(0)
    expect(submittedEvents.length).toBe(0)
    expect(field.value).toBe("#alpha-42 ")
  })
})
