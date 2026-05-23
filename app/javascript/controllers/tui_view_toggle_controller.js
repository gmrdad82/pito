import { Controller } from "@hotwired/stimulus"

/**
 * tui-view-toggle — switches between mutually-exclusive view modes
 * (e.g. month / schedule, day / week, list / grid). The active
 * variant renders with surrounding spaces + a distinct color (active
 * styling lives in the rendered HTML / CSS); the inactive variant is
 * bracketed in the section-accent color.
 *
 * ## Contract
 *
 * - `current-value` (String): the currently-active view name. Updated
 *   in place when the user clicks a different view button. The
 *   server re-renders the surrounding panel body in response to the
 *   dispatched event.
 * - `event-name-value` (String): the CustomEvent name dispatched on
 *   the root element on switch. Defaults to
 *   `tui:view-toggle-changed`. The event detail is `{ view }` where
 *   `view` is the newly-selected name. The event bubbles so the
 *   parent panel can listen anywhere up the tree.
 *
 * ## Keyboard
 *
 * Each rendered button is `data-tui-focusable`, so the surrounding
 * `tui-cursor` controller picks them up as cursorable targets.
 * Activating a focused button (Enter) triggers `click->switch` which
 * runs the same flow as a programmatic activation.
 *
 * ## TUI parity
 *
 * The Ratatui sibling listens to the same conceptual event via the
 * panel-scoped cable channel. Server-side handlers re-broadcast the
 * panel body for both Web + TUI clients.
 */
export default class extends Controller {
  static values = {
    current: String,
    eventName: String
  }

  switch(event) {
    const view = event.params.view
    if (!view || view === this.currentValue) return
    this.currentValue = view
    const name = this.eventNameValue && this.eventNameValue.length > 0
      ? this.eventNameValue
      : "tui:view-toggle-changed"
    this.element.dispatchEvent(new CustomEvent(name, {
      detail: { view },
      bubbles: true
    }))
  }
}
