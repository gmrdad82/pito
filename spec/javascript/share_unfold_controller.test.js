// spec/javascript/share_unfold_controller.test.js
//
// Tests for pito--share-unfold (item 42): the public /share/:uuid chatbox decoy.
//   • Enter (no shift) in the field → clicks the unfold link (navigates).
//   • `c` (outside an editable) → focuses the field.
//   • focus → show "Enter to unfold"; blur → show "c to chat".

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ShareUnfoldController from "controllers/pito/share_unfold_controller"

const tick = () => new Promise((r) => setTimeout(r, 0))

function build() {
  const box = document.createElement("div")
  box.setAttribute("data-controller", "pito--share-unfold")

  const chatHint = document.createElement("span")
  chatHint.setAttribute("data-pito--share-unfold-target", "chatHint")
  box.appendChild(chatHint)

  const unfoldHint = document.createElement("span")
  unfoldHint.setAttribute("data-pito--share-unfold-target", "unfoldHint")
  unfoldHint.className = "hidden"
  box.appendChild(unfoldHint)

  const link = document.createElement("a")
  link.setAttribute("data-pito--share-unfold-target", "link")
  link.href = "/chat/abc"
  box.appendChild(link)

  const field = document.createElement("textarea")
  field.value = "unfold"
  box.appendChild(field)

  document.body.appendChild(box)
  return { box, chatHint, unfoldHint, link, field }
}

describe("pito--share-unfold controller", () => {
  let app

  beforeEach(async () => {
    app = Application.start()
    app.register("pito--share-unfold", ShareUnfoldController)
    await tick()
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  it("shows 'c to chat' (chatHint) and hides 'Enter to unfold' when unfocused", async () => {
    const { chatHint, unfoldHint } = build()
    await tick()
    expect(chatHint.classList.contains("hidden")).toBe(false)
    expect(unfoldHint.classList.contains("hidden")).toBe(true)
  })

  it("swaps to 'Enter to unfold' on focus and back on blur", async () => {
    const { chatHint, unfoldHint, field } = build()
    await tick()

    field.dispatchEvent(new Event("focus"))
    expect(chatHint.classList.contains("hidden")).toBe(true)
    expect(unfoldHint.classList.contains("hidden")).toBe(false)

    field.dispatchEvent(new Event("blur"))
    expect(chatHint.classList.contains("hidden")).toBe(false)
    expect(unfoldHint.classList.contains("hidden")).toBe(true)
  })

  it("Enter in the field clicks the unfold link (navigates), not a newline", async () => {
    const { link, field } = build()
    await tick()
    const clicked = vi.fn()
    link.addEventListener("click", (e) => { e.preventDefault(); clicked() })

    const evt = new KeyboardEvent("keydown", { key: "Enter", cancelable: true, bubbles: true })
    field.dispatchEvent(evt)

    expect(clicked).toHaveBeenCalledOnce()
    expect(evt.defaultPrevented).toBe(true)
  })

  it("Shift+Enter does NOT unfold (allows newline)", async () => {
    const { link, field } = build()
    await tick()
    const clicked = vi.fn()
    link.addEventListener("click", clicked)

    field.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", shiftKey: true, cancelable: true }))
    expect(clicked).not.toHaveBeenCalled()
  })

  it("`c` outside an editable focuses the field", async () => {
    const { field } = build()
    await tick()
    const spy = vi.spyOn(field, "focus")

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", cancelable: true }))
    expect(spy).toHaveBeenCalled()
  })
})
