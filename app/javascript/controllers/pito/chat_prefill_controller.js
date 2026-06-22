// Pito::ChatPrefillController  (pito--chat-prefill)
//
// Makes an identifier token in the SCROLLBACK click-to-type: a click prefills
// the chatbox textarea with a fixed command and focuses it, WITHOUT submitting.
//
//   • a video/game #id  → "show video #<id>" / "show game #<id>"  (Z16)
//   • a reply #hashtag / its shift+r hint → "#<handle> "          (Z18)
//     (handle + trailing space, ready for the user to type a verb)
//
// Wiring (see Pito::Shimmer::TokenComponent `prefill:`, Pito::Event::HandleComponent,
// and the meta-line shift+r Pito::Keybinding::ShortcutComponent):
//   data-controller="pito--chat-prefill"
//   data-action="click->pito--chat-prefill#fill"
//   data-pito--chat-prefill-text-value="<the string to prefill>"
//
// `fill` sets the textarea value, focuses it, moves the caret to the end, and
// dispatches an `input` event so pito--suggestions / pito--draft / the ghost
// react. It never submits.

import { Controller } from "@hotwired/stimulus"

const CHATBOX_SELECTOR = '[data-pito--chat-form-target="inputField"]'

export default class extends Controller {
  static values = { text: String }

  fill(event) {
    const field = document.querySelector(CHATBOX_SELECTOR)
    if (!field) return

    event.preventDefault()

    field.value = this.textValue
    field.focus()
    field.selectionStart = field.selectionEnd = field.value.length
    // Fire input so pito--suggestions / pito--draft / the ghost see the change.
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
