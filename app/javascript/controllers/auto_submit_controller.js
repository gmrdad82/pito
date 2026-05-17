import { Controller } from "@hotwired/stimulus"

// 2026-05-17 — auto-save form controller.
//
// Drop-in for any form that should submit the moment a control inside
// it changes (checkboxes, radios, selects). The controller is bound on
// the form element (or any ancestor of the changing control) and the
// action lives on the control itself, e.g.
//
//     <%= form_with url: ..., data: { controller: "auto-submit" } do |f| %>
//       <%= f.check_box :enabled,
//             { data: { action: "change->auto-submit#submit" } } %>
//     <% end %>
//
// On `change` the controller walks up to the nearest enclosing <form>
// and calls `requestSubmit()` so the browser fires a real `submit`
// event (Turbo intercepts it the same as a user-click submit). No new
// page navigation; the controller returns a Turbo Stream that updates
// the flash region (see _flash_toasts.html.erb).
//
// Used by /settings to auto-save the 4 notification routing flags
// (Discord every / Discord daily, Slack every / Slack daily). Phase C
// keybindings (`da`/`dd`/`sa`/`sd`) `click()` the checkboxes via the
// `[data-leader-toggle]` hooks; the native click flips the checked
// state and dispatches `change`, which this controller catches and
// submits — no extra leader-side wiring required.
export default class extends Controller {
  submit(event) {
    const form = (event && event.target && event.target.closest && event.target.closest("form")) || this.element.closest?.("form") || this.element
    if (!form) return
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else if (typeof form.submit === "function") {
      form.submit()
    }
  }
}
