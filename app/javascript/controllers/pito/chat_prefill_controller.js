// Pito::ChatPrefillController  (pito--chat-prefill)
//
// Makes an identifier token in the SCROLLBACK click-to-type: a click prefills
// the chatbox textarea with a fixed command and focuses it. Depending on the
// `submit` value it either stops there (prefill-only) or immediately fires the
// command (as if the user had pressed Enter).
//
//   • a video/game #id  → "show vid #<id>" / "show game #<id>", submit:true
//     (J5/6/9/12/13/16/20 — click OPENS the entity)
//   • a reply #hashtag / its shift+r hint → "#<handle> ", submit:false
//     (handle + trailing space, ready for the user to type a verb — J18)
//
// Wiring (see Pito::Shimmer::TokenComponent `prefill:` / `submit:`,
// Pito::Event::HandleComponent, and the meta-line shift+r
// Pito::Keybinding::ShortcutComponent):
//   data-controller="pito--chat-prefill"
//   data-action="click->pito--chat-prefill#fill"
//   data-pito--chat-prefill-text-value="<the string to prefill>"
//   data-pito--chat-prefill-submit-value="true"   (optional — auto-submit)
//
// `fill` sets the textarea value, focuses it, moves the caret to the end, and
// dispatches an `input` event so pito--suggestions / pito--draft / the ghost
// react. When `submit` is true it then dispatches a synthetic Enter keydown on
// the textarea so pito--chat-form's EXISTING Enter handler runs verbatim
// (syncHidden → requestSubmit → clear → pito:submitted) — a real Enter, reused.

import { Controller } from "@hotwired/stimulus"

const CHATBOX_SELECTOR = '[data-pito--chat-form-target="inputField"]'

export default class extends Controller {
  static values = { text: String, submit: Boolean }

  fill(event) {
    const field = document.querySelector(CHATBOX_SELECTOR)
    if (!field) return

    event.preventDefault()

    field.value = this.textValue
    field.focus()
    field.selectionStart = field.selectionEnd = field.value.length
    // Fire input so pito--suggestions / pito--draft / the ghost see the change.
    field.dispatchEvent(new Event("input", { bubbles: true }))

    if (!this.submitValue) return

    // Simulate Enter so pito--chat-form's keydown handler submits the command
    // exactly as a real keypress would (it owns syncHidden / requestSubmit /
    // input-clear / the pito:submitted dispatch). Reply #hashtag prefills set
    // submit:false and never reach here, preserving prefill-only behavior.
    field.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Enter",
      bubbles: true,
      cancelable: true
    }))
  }
}
