// Pito::KbdClickController  (pito--kbd-click)
//
// Makes every keyboard-shortcut HINT clickable so the app is usable on
// touch/mobile: tapping a hint synthesizes the SAME event the existing
// keyboard handlers already listen for. It adds NO styling — purely behavior.
//
// Wiring (see Pito::Keybinding::ShortcutComponent + a few raw-span hints):
//   data-controller="pito--kbd-click"
//   data-pito--kbd-click-key-value="<the shortcut text, e.g. ctrl+k>"
//   data-action="click->pito--kbd-click#fire"
//
// The key-value is normalized (case-folded, cmd/meta → ctrl) and looked up in
// HANDLERS below; each handler re-dispatches the keystroke to the element the
// real handler is bound to (the chatbox textarea or `document`).

import { Controller } from "@hotwired/stimulus"

const CHATBOX_SELECTOR = '[data-pito--chat-form-target="inputField"]'

function chatbox() {
  return document.querySelector(CHATBOX_SELECTOR)
}

// Dispatch a synthetic keydown matching what the keyboard handlers expect.
function key(target, init) {
  if (!target) return
  target.dispatchEvent(new KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    ...init,
  }))
}

// Normalized key-value → handler. Keyed so the wiring stays data-driven:
// the component just stamps the raw shortcut text and we resolve it here.
const HANDLERS = {
  // chat_form_controller: Shift+Tab cycles channel scope (textarea-bound).
  // Dispatch WITHOUT focusing — cycling happens in place, focus stays put.
  "shift+tab": () => {
    const field = chatbox()
    if (!field) return
    key(field, { key: "Tab", shiftKey: true })
  },

  // chat_form_controller: Shift+Space cycles stats period (textarea-bound).
  // Dispatch WITHOUT focusing — cycling happens in place, focus stays put.
  "shift+space": () => {
    const field = chatbox()
    if (!field) return
    key(field, { key: " ", code: "Space", shiftKey: true })
  },

  // chat_form_controller: Shift+R reuses last repliable handle — only fires
  // when the caret is at position 0, so move it there first.
  "shift+r": () => {
    const field = chatbox()
    if (!field) return
    field.focus()
    field.selectionStart = field.selectionEnd = 0
    key(field, { key: "R", code: "KeyR", shiftKey: true })
  },

  // chat_form_controller: plain Tab is reserved for autocomplete (textarea-bound).
  "tab": () => {
    const field = chatbox()
    if (!field) return
    field.focus()
    key(field, { key: "Tab" })
  },

  // command_palette_controller's "m": dismiss any open sidebar + focus chatbox.
  // We reproduce that handler's effect directly (it gates on activeElement, so
  // a synthetic document keydown would be unreliable right after a tap).
  "m": () => {
    if (document.querySelector("#pito-sidebar aside")) {
      window.dispatchEvent(new CustomEvent("pito:resume:dismiss"))
    }
    const field = chatbox()
    if (field) {
      field.focus({ preventScroll: true })
      field.selectionStart = field.selectionEnd = field.value.length
    }
  },

  // command_palette_controller: global document keydown handlers.
  "ctrl+k": () => key(document, { key: "k", ctrlKey: true }),
  "ctrl+/": () => key(document, { key: "/", ctrlKey: true }),

  // Esc closes palettes / sidebars (handled on document by several controllers).
  "esc": () => key(document, { key: "Escape" }),

  // command_palette_controller: Ctrl+n opens sidebar + renames current conv.
  "n": () => key(document, { key: "n", ctrlKey: true }),

  // notifications "space" toggle hint (document-bound).
  "space": () => key(document, { key: " " }),
}

// case-fold + map cmd/meta → ctrl so "Esc", "Cmd+K", etc. all resolve.
function normalize(value) {
  return (value || "")
    .trim()
    .toLowerCase()
    .replace(/^cmd\+/, "ctrl+")
    .replace(/^meta\+/, "ctrl+")
}

export default class extends Controller {
  static values = { key: String }

  // mousedown fires before the tap moves focus. Preventing its default keeps the
  // chatbox from blurring when a hint chip is tapped — otherwise the focusout
  // swaps the focused-state hints (shift+tab / shift+space) away mid-tap and the
  // mobile keyboard dismisses. Handlers that DO want focus (m / tab) set it
  // themselves. The classic "toolbar button that doesn't steal focus" pattern.
  hold(event) {
    event.preventDefault()
  }

  fire(event) {
    const handler = HANDLERS[normalize(this.keyValue)]
    if (!handler) return
    event.preventDefault()
    // Don't also bubble to the chatbox wrapper's click->chat-form#focusField:
    // each handler manages focus itself (cyclers stay in place; m/tab focus).
    event.stopPropagation()
    handler()
  }
}
