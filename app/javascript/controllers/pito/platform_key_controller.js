// Pito::PlatformKeyController
//
// Swaps a keyboard-shortcut label to its macOS variant when running on a Mac.
// The server renders the Win/Linux default (e.g. "Ctrl+K"); on a Mac this
// replaces the element's text with the mac value (e.g. "Cmd+K"). Modern
// browsers only — no fallback.
//
// Markup:
//   <span data-controller="pito--platform-key"
//         data-pito--platform-key-mac-value="Cmd+K">Ctrl+K</span>

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { mac: String }

  connect() {
    if (this.hasMacValue && this.#isMac()) {
      this.element.textContent = this.macValue
    }
  }

  #isMac() {
    const platform = navigator.userAgentData?.platform || navigator.platform || ""
    return /mac|iphone|ipad|ipod/i.test(platform)
  }
}
