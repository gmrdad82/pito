// Pito::ChatFormController
//
// Stimulus controller for the terminal chatbox form.
// Captures Enter (no Shift) on the input target → submits via Turbo, clears input.
// Shift+TAB cycles channels; Shift+SPACE cycles periods (authenticated only).
// Plain TAB is reserved for autocomplete (not handled here).
//
// Targets:
//   inputField     — the <textarea> (data-pito--chat-form-target="inputField")
//   hiddenInput    — a hidden <input> whose value gets set before submit
//   channelDisplay — the visible channel token in the filter line
//   periodDisplay  — the visible period token in the filter line
//   channelInput   — hidden input carrying params[:channel]
//   periodInput    — hidden input carrying params[:period]
//
// Values:
//   channels — Array of channel handles (e.g. ["@all", "@gaming"])
//   periods  — Array of period strings (default: ["7d", "28d", "1m", "3m", "1y", "lifetime"])

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"

export default class extends Controller {
  static targets = ["inputField", "hiddenInput", "channelDisplay", "periodDisplay", "channelInput", "periodInput"]

  static values = {
    channels: Array,
    periods: { type: Array, default: ["7d", "28d", "1m", "3m", "1y", "lifetime"] }
  }

  connect() {
    this.#syncHidden()
  }

  // Click anywhere on the chatbox wrapper → focus the textarea
  focusField(event) {
    if (event.target !== this.inputFieldTarget) {
      this.inputFieldTarget.focus({ preventScroll: true })
    }
  }

  handleKeydown(event) {
    if (!isAuthenticated()) return

    if (event.key === "Tab" && !event.shiftKey) {
      // Reserved for autocomplete — do not preventDefault, do not cycle.
      return
    }

    if (event.key === "Tab" && event.shiftKey) {
      event.preventDefault()
      this.#cycleNext(this.channelsValue, "channelInput", "channelDisplay")
      return
    }

    if (event.code === "Space" && event.shiftKey) {
      event.preventDefault()
      this.#cycleNext(this.periodsValue, "periodInput", "periodDisplay")
      return
    }

    if (event.key !== "Enter" || event.shiftKey) return

    // Cable dead after inactivity — reload to re-establish the WebSocket
    if (document.body.dataset.pitoCableOffline === "true") {
      event.preventDefault()
      window.location.reload()
      return
    }

    const hasInput = this.inputFieldTarget.value.trim().length > 0
    event.preventDefault()
    this.#syncHidden()
    this.element.requestSubmit()
    this.inputFieldTarget.value = ""
    this.inputFieldTarget.dispatchEvent(new Event("input", { bubbles: true }))

    if (hasInput) {
      document.dispatchEvent(new CustomEvent("pito:submitted"))
    }
  }

  #cycleNext(list, inputTarget, displayTarget) {
    if (!list || list.length === 0) return
    if (!this.targets.has(inputTarget) || !this.targets.has(displayTarget)) return

    const input = this.targets.find(inputTarget)
    const display = this.targets.find(displayTarget)
    const current = input.value
    let idx = list.indexOf(current)
    if (idx === -1) idx = 0
    const next = list[(idx + 1) % list.length]
    input.value = next

    const cyan = display.querySelector(".text-cyan")
    if (cyan) {
      cyan.textContent = next
    } else {
      display.textContent = next
    }
  }

  #syncHidden() {
    this.hiddenInputTarget.value = this.inputFieldTarget.value
  }
}
