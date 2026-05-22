import { Controller } from "@hotwired/stimulus"

/**
 * tui-mode-lozenge — thin delegator for the Bottom Status Bar mode lozenge.
 *
 * Listens for `tui:mode-changed` on document (broadcast by tui-cursor) and
 * updates the colocated tui-transition outlet with the new mode's word +
 * color. The actual scramble-settle + color-crossfade is owned by the
 * canonical tui-transition controller — this controller is a pure
 * dispatcher.
 *
 * Mode → color map (MUST mirror Tui::ModeLozengeComponent::COLORS):
 *   normal  → muted
 *   insert  → accent
 *   command → accent
 *   search  → success
 *
 * Pre-rendered i18n words for each mode arrive via data attrs on the host:
 *   data-tui-mode-lozenge-normal-value
 *   data-tui-mode-lozenge-insert-value
 *   data-tui-mode-lozenge-command-value
 *   data-tui-mode-lozenge-search-value
 *
 * Outlets:
 *   tui-transition — the colocated transition controller (same element, so
 *                    the outlet selector resolves to the host itself).
 *
 * @contract see docs/design.md § Transitions
 */
export default class extends Controller {
  static outlets = ["tui-transition"]

  static COLOR_FOR_MODE = {
    normal:  "muted",
    insert:  "accent",
    command: "accent",
    search:  "success"
  }

  connect() {
    this._boundChanged = this.onModeChanged.bind(this)
    document.addEventListener("tui:mode-changed", this._boundChanged)
  }

  disconnect() {
    if (this._boundChanged) {
      document.removeEventListener("tui:mode-changed", this._boundChanged)
      this._boundChanged = null
    }
  }

  onModeChanged(event) {
    if (!this.hasTuiTransitionOutlet) return
    const mode = (event?.detail?.mode || "normal").toString()
    const color = this.constructor.COLOR_FOR_MODE[mode] || "muted"
    const word  = this.element.getAttribute(`data-tui-mode-lozenge-${mode}-value`) || mode
    this.tuiTransitionOutlet.setColor(color)
    this.tuiTransitionOutlet.setValue(word)
  }
}
