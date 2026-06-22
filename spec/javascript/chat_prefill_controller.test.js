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

function build(text) {
  document.body.innerHTML = `
    <form id="chat-form">
      <textarea data-pito--chat-form-target="inputField"></textarea>
    </form>
    <span
      data-controller="pito--chat-prefill"
      data-action="click->pito--chat-prefill#fill"
      data-pito--chat-prefill-text-value="${text}"
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

  it("never submits the form", async () => {
    const token = build("#alpha-42 ")
    await Promise.resolve()

    const form = document.getElementById("chat-form")
    const onSubmit = vi.fn((e) => e.preventDefault())
    form.addEventListener("submit", onSubmit)

    token.click()

    expect(onSubmit).not.toHaveBeenCalled()
    expect(document.querySelector('[data-pito--chat-form-target="inputField"]').value).toBe("#alpha-42 ")
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
