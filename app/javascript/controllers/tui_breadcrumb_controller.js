import { Controller } from "@hotwired/stimulus"

/**
 * tui-breadcrumb — thin delegator. Listens for `tui:panel-focus-changed`
 * (broadcast by tui_cursor_controller.js) and formats the new value
 * (panel + optional sub_panel) into the colocated tui-transition outlet.
 *
 * Beta 4 Phase 2E — multi-color segments via tui-transition's
 * segmentsValue. The breadcrumb now has 3 visual states:
 *
 *   1. idle (no panel focused)
 *        value:    <screen name>     e.g. "home"
 *        color:    accent-pale       (host color — washed-out home-accent)
 *        segments: <empty>
 *
 *   2. panel only
 *        value:    <panel>           e.g. "security"
 *        color:    accent            (host color)
 *        segments: <empty>
 *
 *   3. panel + sub-panel
 *        value:    <panel>:(<sub>)   e.g. "security:(totp)"
 *        color:    accent-pale       (host color; segments override)
 *        segments: [
 *          { name: "panel_title",     range: [0, panel.length],         color: "accent-pale" },
 *          { name: "sub_panel_title", range: [panel.length+2, sub_end], color: "accent" }
 *        ]
 *        // ":(" and ")" delimiters inherit the host accent-pale color.
 *
 * The transition controller scrambles only the chars that differ
 * (diff-only) and applies color-crossfade between host colors. Per-char
 * colors come from applySegments() reading the segmentsValue attribute.
 *
 * Format shape mirrors `Tui::BreadcrumbComponent.format` in Ruby:
 *   - format(panel, null)       → "<panel>"
 *   - format(panel, subPanel)   → "<panel>:(<subPanel>)"
 *
 * The screen name is intentionally NOT part of the formatted value
 * (Phase 2E regression from Phase 2D). It's the IDLE fallback only —
 * the top-status-bar ScreensList component shows the active screen.
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
 * @contract see app/components/tui/breadcrumb_component.rb
 */
export default class extends Controller {
  static outlets = ["tui-transition"]
  static values = { screen: String }

  // Buffered [panel, subPanel] pair when applyState is called before the
  // tui-transition outlet controller has connected. Flushed by
  // tuiTransitionOutletConnected() once the outlet is ready.
  _pendingState = null

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
    this._pendingState = null
  }

  // Stimulus lifecycle — fires when the tui-transition outlet controller
  // actually connects (not just when its element appears in the DOM).
  // Flushes any state buffered before the outlet was ready.
  tuiTransitionOutletConnected(_controller, _element) {
    if (this._pendingState) {
      const [panel, subPanel] = this._pendingState
      this._pendingState = null
      this.applyState(panel, subPanel)
    }
  }

  onPanelFocusChanged(event) {
    const detail = event?.detail || {}
    const panel = detail.panel ?? detail.title ?? ""
    const subPanel = detail.subPanel || ""
    this._applyOrBuffer(panel, subPanel)
  }

  // Seed from the currently focused panel so a late connect (after
  // tui-cursor's initial event already fired) still paints correctly.
  seedFromFocusedPanel() {
    const focused = document.querySelector(
      '[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]'
    )
    const panel = focused?.dataset?.panelTitle || ""
    if (!panel) return
    const subFocused = focused.querySelector(
      '[data-tui-cursor-target="sub-panel"][data-tui-cursor-sub-panel-focused="yes"]'
    )
    const subPanel = subFocused?.dataset?.panelTitle || ""
    this._applyOrBuffer(panel, subPanel)
  }

  // Attempt to apply state immediately; buffer for outlet-connected flush
  // if the outlet element exists but its controller is not yet booted.
  _applyOrBuffer(panel, subPanel) {
    if (!this.hasTuiTransitionOutlet) {
      // No outlet element at all yet — buffer and wait.
      this._pendingState = [panel, subPanel]
      return
    }
    try {
      this.applyState(panel, subPanel)
    } catch (err) {
      // Outlet element found but controller not yet connected (Stimulus
      // race on initial page load). Buffer and let tuiTransitionOutletConnected
      // flush once the outlet controller is ready.
      if (err && err.message && err.message.includes("missing an outlet controller")) {
        this._pendingState = [panel, subPanel]
        return
      }
      throw err
    }
  }

  applyState(panel, subPanel) {
    let value
    let color
    let segments

    if (!panel) {
      // Idle: show the screen name in accent-pale (washed-out home-accent
      // purple — distinct from --color-muted which AppVersion owns).
      value = this.screenValue
      color = "accent-pale"
      segments = ""
    } else if (!subPanel) {
      // Panel only: the whole value is accent.
      value = panel
      color = "accent"
      segments = ""
    } else {
      // Panel + sub-panel: host accent-pale; segments force the
      // sub-panel range to accent. The ":(" / ")" delimiters inherit
      // the host accent-pale color.
      value = `${panel}:(${subPanel})`
      color = "accent-pale"
      const panelEnd = panel.length
      const subStart = panelEnd + 2 // +2 for the ":(" delimiter
      const subEnd = subStart + subPanel.length
      segments = JSON.stringify([
        { name: "panel_title",     range: [0, panelEnd],            color: "accent-pale" },
        { name: "sub_panel_title", range: [subStart, subEnd],       color: "accent" }
      ])
    }

    // Push the segments descriptor first so tui-transition's
    // segmentsValueChanged callback owns the post-render class flip; then
    // push value + color so animateDiff replays applySegments() and the
    // new colors land on the new cells.
    this.tuiTransitionOutlet.element.setAttribute(
      "data-tui-transition-segments-value",
      segments
    )
    this.tuiTransitionOutlet.setColor(color)
    this.tuiTransitionOutlet.setValue(value)
  }

  // Mirror of Tui::BreadcrumbComponent.format. Exposed for parity tests
  // and for callers that need the same string Ruby would derive.
  format(panel, subPanel) {
    if (!panel) return ""
    if (!subPanel) return panel
    return `${panel}:(${subPanel})`
  }
}
