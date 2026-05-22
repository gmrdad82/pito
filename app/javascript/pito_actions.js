/**
 * @module pito_actions
 *
 * @contract
 * Single entry point for user-triggerable actions per ADR 0018.
 * Every consumer (mouse click on a [reindex] button, `:reindex Meilisearch`
 * palette command, future leader menu, future MCP click) calls
 * `Pito.dispatchAction(name)`.
 *
 * Reads the action registry from `<meta name="pito-actions" content="JSON">`.
 *
 * If the action has `confirmation:`, dispatches the
 * `pito:action:confirm-requested` event the existing confirmation dialog
 * listens to. On confirm the dialog re-targets its form to the action's
 * `path` + submits Turbo-driven; the controller responds 204 no_content
 * and cable broadcasts handle the UI update.
 *
 * @testability
 * Behavioral contract above is the spec. No JS unit tests in this project
 * (no Capybara, no system specs). The backing Ruby surfaces
 * (`Pito::ActionRegistry`, `Pito::CableBroadcaster`, the
 * `Tui::ConfirmationDialogComponent`) carry spec coverage.
 */

const PITO = {
  dispatchAction(name) {
    const meta = document.querySelector('meta[name="pito-actions"]')
    if (!meta) throw new Error("Pito.dispatchAction: <meta name=pito-actions> missing")
    const registry = JSON.parse(meta.content)
    const action = registry[name]
    if (!action) throw new Error(`Pito.dispatchAction: unknown action ${name}`)

    if (action.confirmation) {
      this._openConfirmation(action)
    } else {
      this._submit(action)
    }
  },

  _openConfirmation(action) {
    // Hand off to whichever dialog controller listens for this event.
    // The `Tui::ConfirmationDialogComponent` instance reads `event.detail`
    // and re-targets its form before calling `showModal()`.
    document.dispatchEvent(new CustomEvent("pito:action:confirm-requested", {
      detail: action
    }))
  },

  _submit(action) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = action.path
    form.style.display = "none"

    const csrfMeta = document.querySelector('meta[name="csrf-token"]')
    if (csrfMeta) {
      const csrf = document.createElement("input")
      csrf.type = "hidden"
      csrf.name = "authenticity_token"
      csrf.value = csrfMeta.content
      form.appendChild(csrf)
    }

    if (action.method && action.method !== "post") {
      const methodInput = document.createElement("input")
      methodInput.type = "hidden"
      methodInput.name = "_method"
      methodInput.value = action.method
      form.appendChild(methodInput)
    }

    document.body.appendChild(form)
    form.requestSubmit()
  }
}

window.Pito = PITO
export default PITO
