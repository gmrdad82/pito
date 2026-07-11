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
//   periods  — Array of period strings (default: ["7d", "28d", "3m", "1y", "lifetime"])
//
// Picker integration:
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
    periods: { type: Array, default: ["7d", "28d", "3m", "1y", "lifetime"] },
    uuid: String
  }

  connect() {
    this.#syncHidden()
    // Listen for picker selections and drive form submission.
    this._onPickerSelect = (e) => this.fillAndSubmit(e)
    document.addEventListener("pito:picker:select", this._onPickerSelect)
    // Global shift+r listener: fires the reply shortcut even when the chatbox
    // is not focused (e.g. user is reading the scrollback).
    this._onGlobalReply = (e) => this.#handleGlobalReply(e)
    document.addEventListener("keydown", this._onGlobalReply)
  }

  disconnect() {
    document.removeEventListener("pito:picker:select", this._onPickerSelect)
    document.removeEventListener("keydown", this._onGlobalReply)
  }

  // Public action for pickers (games, future IGDB picker, etc.).
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
        // shift+tab cycles the channel ONLY while its hint is visible
        // (focused + `list vids/games`); inert otherwise.
        event.preventDefault()
        if (this.#displayVisible("channelDisplay")) {
          this.#cycleNext(this.channelsValue, "channelInput", "channelDisplay")
          this.#persistScope()
        }
        return
      }

      if (event.code === "Space" && event.shiftKey) {
        // shift+space cycles the period ONLY while its hint is visible
        // (focused + `analyze`); inert otherwise.
        event.preventDefault()
        if (this.#displayVisible("periodDisplay")) {
          this.#cycleNext(this.periodsValue, "periodInput", "periodDisplay")
          this.#persistScope()
        }
        return
      }

      // Shift+R at the very start of the field → reuse the most recent
      // command's repliable hashtag(s) without retyping. Only fires when the
      // caret is at position 0 so it never hijacks a literal "R" mid-line.
      // Plain Shift+R only — never when Ctrl/Meta/Alt is held, so the browser's
      // Ctrl+Shift+R (hard reload) and other shortcuts pass straight through.
      //
      //   • exactly one live handle → prepend `#<handle> ` directly.
      //   • more than one live handle → open the hashtag picker: the last
      //     command may have emitted several repliable messages, so let the user
      //     pick which one to act on. The picker prefills without submitting.
      //   • zero live handles → no-op (let the keystroke pass through).
      if (event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey && event.code === "KeyR") {
        const field = this.inputFieldTarget
        if (field.selectionStart === 0 && field.selectionEnd === 0) {
          if (this.#startReply()) event.preventDefault()
        }
        return
      }
    }

    if (event.key !== "Enter" || event.shiftKey) return

    // Submit ALWAYS — the message POSTs over HTTP, independent of the WebSocket.
    // (We used to reload here when the cable was flagged offline, which silently
    // discarded what the user typed; the cable reconnects on its own / on the
    // tab-visibility recovery in pito--cable-health.)
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

    // Target the plain token span (current), or the legacy shimmer/cyan spans.
    const token = display.querySelector(".pito-token, .pito-reference-shimmer, .text-cyan")
    if (token) {
      token.textContent = next
    } else {
      display.textContent = next
    }
  }

  // Reuse the most recent command's repliable hashtag(s).
  // Returns true when it acted (handles present), false when it was a no-op.
  #startReply() {
    const handles = this.#lastTurnHandles()
    if (handles.length > 1) {
      document.dispatchEvent(new CustomEvent("pito:hashtag-picker:open", { detail: { handles } }))
      return true
    } else if (handles.length === 1) {
      const field = this.inputFieldTarget
      const insert = `#${handles[0]} `
      field.value = insert + field.value
      field.selectionStart = field.selectionEnd = insert.length
      field.dispatchEvent(new Event("input", { bubbles: true }))
      return true
    }
    return false
  }

  // Global keydown listener: fires shift+r reply even when the chatbox textarea
  // is not focused (user reading scrollback). Skips when focus is in any other
  // editable element so it never hijacks typing elsewhere.
  #handleGlobalReply(event) {
    if (!isAuthenticated()) return
    if (!(event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey && event.code === "KeyR")) return

    const ae = document.activeElement
    if (ae === this.inputFieldTarget) return // handled by textarea's own keydown
    const editable = ae && (ae.tagName === "INPUT" || ae.tagName === "TEXTAREA" || ae.isContentEditable)
    if (editable) return // don't hijack typing in another field

    event.preventDefault()
    this.inputFieldTarget.focus({ preventScroll: true })
    this.#startReply()
  }

  // The live hashtag handles emitted by the user's most recent command.
  //
  // A single command can broadcast several repliable messages, each rendering
  // its own `[data-pito-handle]` token — but only while LIVE: a consumed or
  // resolved follow-up drops the token entirely (the HandleComponent isn't
  // rendered), so anything still in the DOM is by definition still repliable.
  //
  // We scope to the turn that owns the most recent live handle (the same
  // segment the pito--lasthashtag controller paints the `shift+r` hint on) and
  // return every live handle within it, de-duplicated, in document order.
  // Returns `[]` when the scrollback holds no live handles.
  #lastTurnHandles() {
    const scrollback = document.getElementById("pito-scrollback")
    const root = scrollback || document
    const nodes = root.querySelectorAll("[data-pito-handle]")
    if (nodes.length === 0) return []

    const lastNode = nodes[nodes.length - 1]
    const turn = lastNode.closest(".pito-turn") || root

    const seen = new Set()
    const handles = []
    turn.querySelectorAll("[data-pito-handle]").forEach((node) => {
      const handle = node.dataset.pitoHandle
      if (handle && !seen.has(handle)) {
        seen.add(handle)
        handles.push(handle)
      }
    })
    return handles
  }

  // Persist the current channel scope (shift+tab) and stats period (shift+space)
  // to the conversation so a reload restores them. Fire-and-forget PATCH mirroring
  // pito--draft's autosave; a failure is non-fatal (the next cycle retries).
  #persistScope() {
    if (!this.uuidValue) return
    if (!this.targets.has("channelInput") || !this.targets.has("periodInput")) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(`/chat/${this.uuidValue}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
      },
      body: JSON.stringify({
        scope_channel: this.targets.find("channelInput").value,
        stats_period: this.targets.find("periodInput").value,
      }),
    }).catch((err) => {
      console.warn("[pito--chat-form] scope PATCH failed:", err)
    })
  }

  // True when a display span (channelDisplay / periodDisplay) is currently shown —
  // i.e. chatbox-hints has revealed its cycler for the typed verb/noun.
  #displayVisible(displayTarget) {
    return this.targets.has(displayTarget) &&
      !this.targets.find(displayTarget).classList.contains("hidden")
  }

  #syncHidden() {
    this.hiddenInputTarget.value = this.inputFieldTarget.value

    // Send the channel ONLY when shift+tab is visible (list vids/games), the period
    // ONLY when shift+space is visible (analyze). A DISABLED input keeps its cycled
    // value (so the cycling flow is preserved) but is omitted from the POST → the
    // backend falls back to its defaults (channel @all, period nil); no other
    // verb/noun evaluates channel or period.
    if (this.hasChannelInputTarget) this.channelInputTarget.disabled = !this.#displayVisible("channelDisplay")
    if (this.hasPeriodInputTarget)  this.periodInputTarget.disabled  = !this.#displayVisible("periodDisplay")

    // Tell the backend how wide the scrollback is right now, so `list` can
    // auto-fill table columns to fit (the table isn't sparse on a wide screen).
    if (this.hasViewportWidthTarget) {
      const scrollback = document.getElementById("pito-scrollback")
      this.viewportWidthTarget.value = scrollback ? scrollback.clientWidth : ""
    }
  }
}
