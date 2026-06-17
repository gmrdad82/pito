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
//
// Picker integration (T10.9):
//   Listens for `pito:picker:select` on `document`.  When fired the event's
//   `detail.command` is written into the textarea and the form is submitted
//   immediately, so picker selections drive a full chat submission without the
//   user having to type anything.

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"

export default class extends Controller {
  static targets = ["inputField", "hiddenInput", "channelDisplay", "periodDisplay", "channelInput", "periodInput", "viewportWidth"]

  static values = {
    channels: Array,
    periods: { type: Array, default: ["7d", "28d", "1m", "3m", "1y", "lifetime"] }
  }

  connect() {
    this.#syncHidden()
    // T10.9: listen for picker selections and drive form submission.
    this._onPickerSelect = (e) => this.fillAndSubmit(e)
    document.addEventListener("pito:picker:select", this._onPickerSelect)
  }

  disconnect() {
    document.removeEventListener("pito:picker:select", this._onPickerSelect)
  }

  // T10.9 — Public action for pickers (games, future IGDB picker, etc.).
  // Sets the textarea to `event.detail.command` and submits the form exactly
  // as if the user had typed the command and pressed Enter.
  fillAndSubmit(event) {
    const command = event?.detail?.command
    if (!command) return

    const field = this.inputFieldTarget
    field.value = command
    // Fire input so pito--suggestions and pito--draft see the change.
    field.dispatchEvent(new Event("input", { bubbles: true }))
    this.#syncHidden()
    this.element.requestSubmit()
    field.value = ""
    field.dispatchEvent(new Event("input", { bubbles: true }))
    document.dispatchEvent(new CustomEvent("pito:submitted"))
  }

  // Click anywhere on the chatbox wrapper → focus the textarea
  focusField(event) {
    if (event.target !== this.inputFieldTarget) {
      this.inputFieldTarget.focus({ preventScroll: true })
    }
  }

  handleKeydown(event) {
    // Tab autocomplete + channel/period cycling are authenticated-only
    // conveniences. Enter-to-submit must work for EVERYONE — an unauthenticated
    // visitor has to be able to send `/login <code>`.
    if (isAuthenticated()) {
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

      // Shift+R at the very start of the field → prepend the most recent
      // hashtag handle (`#<handle> `) so you can act on the last segment
      // without retyping it. Only fires when the caret is at position 0 so it
      // never hijacks a literal "R" mid-line. Plain Shift+R only — never when
      // Ctrl/Meta/Alt is held, so the browser's Ctrl+Shift+R (hard reload) and
      // other shortcuts pass straight through.
      if (event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey && event.code === "KeyR") {
        const field = this.inputFieldTarget
        if (field.selectionStart === 0 && field.selectionEnd === 0) {
          const handle = this.#lastHandle()
          if (handle) {
            event.preventDefault()
            const insert = `#${handle} `
            field.value = insert + field.value
            field.selectionStart = field.selectionEnd = insert.length
            field.dispatchEvent(new Event("input", { bubbles: true }))
          }
        }
        return
      }
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

  // The handle of the most recent hashtag-bearing segment in the scrollback,
  // or null if there is none. Kept in sync with the `· shift+r` affordance the
  // pito--lasthashtag controller paints on that same (last) segment.
  #lastHandle() {
    const nodes = document.querySelectorAll("[data-pito-handle]")
    const last = nodes[nodes.length - 1]
    return last?.dataset.pitoHandle || null
  }

  #syncHidden() {
    this.hiddenInputTarget.value = this.inputFieldTarget.value

    // Tell the backend how wide the scrollback is right now, so `list` can
    // auto-fill table columns to fit (the table isn't sparse on a wide screen).
    if (this.hasViewportWidthTarget) {
      const scrollback = document.getElementById("pito-scrollback")
      this.viewportWidthTarget.value = scrollback ? scrollback.clientWidth : ""
    }
  }
}
