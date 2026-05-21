import { Controller } from "@hotwired/stimulus";

/**
 * @controller action-trigger
 *
 * @contract
 * Generic action-bus dispatch handler. Wired by `Tui::ActionButtonComponent`.
 * On click, reads `data-action-name` from the button and routes through
 * `window.Pito.dispatchAction(name)` (ADR 0018). `window.Pito` is loaded
 * via `app/javascript/pito_actions.js`.
 *
 * @testability
 * No JS unit tests in this project. Behaviour is locked by `Pito::ActionRegistry`
 * + `Tui::ActionButtonComponent` specs on the Ruby side.
 */
export default class extends Controller {
  dispatch(event) {
    if (event) event.preventDefault();
    const actionName = this.element.dataset.actionName;
    if (!actionName) return;
    if (window.Pito && typeof window.Pito.dispatchAction === "function") {
      window.Pito.dispatchAction(actionName);
    }
  }
}
