// spec/javascript/autosize_controller.test.js
//
// Tests for pito/autosize_controller.js — the functional remainder of the old
// terminal-caret controller: it auto-grows the chatbox <textarea> and (when the
// autofocus value is set) focuses it with the caret at the end of any draft.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import AutosizeController from "controllers/pito/autosize_controller"

function buildDOM({ autofocus = false, value = "" } = {}) {
  document.body.innerHTML = `
    <div class="pito-chatbox__field-wrap"
         data-controller="pito--autosize"
         data-pito--autosize-autofocus-value="${autofocus}">
      <textarea data-pito--autosize-target="field">${value}</textarea>
    </div>
  `
  return document.querySelector("textarea")
}

describe("AutosizeController", () => {
  let app

  beforeEach(async () => {
    app = Application.start()
    app.register("pito--autosize", AutosizeController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
  })

  it("autofocuses the field and moves the caret to the end when autofocus is true", async () => {
    const field = buildDOM({ autofocus: true, value: "hello" })
    await Promise.resolve()

    expect(document.activeElement).toBe(field)
    expect(field.selectionStart).toBe(5)
    expect(field.selectionEnd).toBe(5)
  })

  it("does not focus the field when autofocus is false", async () => {
    const field = buildDOM({ autofocus: false, value: "hi" })
    await Promise.resolve()

    expect(document.activeElement).not.toBe(field)
  })

  it("locks the textarea to an explicit pixel height on connect (autosize)", async () => {
    const field = buildDOM({ value: "line" })
    await Promise.resolve()

    expect(field.style.height).toMatch(/px$/)
  })

  it("re-grows on input without throwing", async () => {
    const field = buildDOM({ value: "" })
    await Promise.resolve()

    field.value = "a\nb\nc"
    expect(() => field.dispatchEvent(new Event("input", { bubbles: true }))).not.toThrow()
    expect(field.style.height).toMatch(/px$/)
  })
})
