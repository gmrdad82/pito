import { Controller } from "@hotwired/stimulus"

/**
 * tui-breadcrumb — thin delegator. Listens for `tui:panel-focus-changed`
 * (broadcast by tui_cursor_controller.js) and formats the new value
 * (screen + panel + sub_panel) into the colocated tui-transition outlet.
 *
 * The transition controller scrambles only the chars that differ
 * (diff-only) and applies color-crossfade between muted (no panel
 * focused) and accent (panel focused).
 *
 * Format shape mirrors `Tui::BreadcrumbComponent.format` in Ruby:
 *   - screen only             → "home"
 *   - screen + panel          → "home security"
 *   - screen + panel + sub    → "home security:(notifications)"
 *
 * Event contract (set by tui_cursor_controller.js):
 *
 *   detail: {
 *     panel:     "<panel title>" | undefined,
 *     title:     "<panel title>" | undefined,   // alternate key tui-cursor used
 *     subPanel:  "<sub-panel title>" | null
 *   }
 *
 * @contract see docs/design.md § Transitions
 */
export default class extends Controller {
  static outlets = ["tui-transition"]
  static values = { screen: String }

  connect() {
    this.boundFocus = this.onPanelFocusChanged.bind(this)
    document.addEventListener("tui:panel-focus-changed", this.boundFocus)
    this.seedFromFocusedPanel()
  }

  disconnect() {
    if (this.boundFocus) {
      document.removeEventListener("tui:panel-focus-changed", this.boundFocus)
      this.boundFocus = null
    }
  }

  onPanelFocusChanged(event) {
    if (!this.hasTuiTransitionOutlet) return
    const detail = event?.detail || {}
    const panel = detail.panel ?? detail.title ?? ""
    const subPanel = detail.subPanel || ""
    this.applyState(panel, subPanel)
  }

  // Seed from the currently focused panel so a late connect (after
  // tui-cursor's initial event already fired) still paints correctly.
  seedFromFocusedPanel() {
    if (!this.hasTuiTransitionOutlet) return
    const focused = document.querySelector(
      '[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]'
    )
    const panel = focused?.dataset?.panelTitle || ""
    if (!panel) return
    const subFocused = focused.querySelector(
      '[data-tui-cursor-target="sub-panel"][data-tui-cursor-sub-panel-focused="yes"]'
    )
    const subPanel = subFocused?.dataset?.panelTitle || ""
    this.applyState(panel, subPanel)
  }

  applyState(panel, subPanel) {
    const formatted = this.format(this.screenValue, panel, subPanel)
    this.tuiTransitionOutlet.setValue(formatted)
    this.tuiTransitionOutlet.setColor(panel ? "accent" : "muted")
  }

  format(screen, panel, subPanel) {
    if (!panel) return screen
    if (!subPanel) return `${screen} ${panel}`
    return `${screen} ${panel}:(${subPanel})`
  }
}
