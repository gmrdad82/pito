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

// 2026-05-24 — client-side action whitelist. Actions in this map run
// entirely in JS (no path lookup through the action registry). The
// leader menu / palette / any other dispatcher hands them off here.
//
// 2026-05-25 (sync-rebuild) — `toggle_tst_sync` now POSTs to
// `/sync/toggle?target=app`. Server cascades the write across every
// known sync target (Pito::SyncTargets.cascade_targets("app")) and
// broadcasts a sync-state envelope per cascaded target on the
// `pito:sync_state` channel. The bridge below (see initSyncBridge)
// converts each broadcast into a `tui:sync-changed` document event
// every sync-indicator VC already listens for.
const CLIENT_ACTIONS = {
  toggle_tst_sync() {
    postSyncToggle("app")
    // Optimistic notice. The cable broadcast still drives the glyph
    // repaint; the notice copy is read from <meta name=pito-notices>
    // (mirroring per-panel toggles), with the user's most recent
    // cached value as the optimism source. When the cache is unset,
    // we default to "currently enabled" (the documented unset = yes
    // semantic) and so the toggle is optimistically heading to OFF.
    const wasEnabled = window.__pitoSyncStateCache &&
      window.__pitoSyncStateCache["app"] !== undefined
      ? window.__pitoSyncStateCache["app"] : true
    const nextEnabled = !wasEnabled
    const message = readNoticeI18n(nextEnabled ? "sync_resumed" : "sync_paused")
    if (message) {
      document.dispatchEvent(new CustomEvent("tui:notice", {
        detail: { message, severity: "info" }
      }))
    }
  }
}

// POSTs to /sync/toggle?target=<target>. Same wire shape as the
// per-target sync VC click handler. CSRF token pulled from the
// standard <meta name="csrf-token"> element.
function postSyncToggle(target) {
  const csrfMeta = document.querySelector('meta[name="csrf-token"]')
  const headers = { "X-Requested-With": "XMLHttpRequest", "Accept": "application/json" }
  if (csrfMeta) headers["X-CSRF-Token"] = csrfMeta.content
  fetch(`/sync/toggle?target=${encodeURIComponent(target)}`, {
    method: "POST",
    headers,
    credentials: "same-origin"
  })
}

// Reads the resolved i18n string for a notice key out of the
// `<meta name="pito-notices" content="JSON">` payload emitted by the
// layout. Returns the string when present, or null when the meta is
// missing / the key is absent (caller decides whether to fire a
// fallback). Centralized here so every JS-side notice emitter shares
// one lookup contract.
function readNoticeI18n(key) {
  const meta = document.querySelector('meta[name="pito-notices"]')
  if (!meta) return null
  let map
  try { map = JSON.parse(meta.content) } catch (_) { return null }
  if (!map || typeof map !== "object") return null
  const value = map[key]
  return typeof value === "string" ? value : null
}

const PITO = {
  dispatchAction(name) {
    // 2026-05-24 — client-side action short-circuit. Avoids the
    // registry / POST roundtrip for actions defined entirely in JS.
    if (Object.prototype.hasOwnProperty.call(CLIENT_ACTIONS, name)) {
      CLIENT_ACTIONS[name]()
      return
    }
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
