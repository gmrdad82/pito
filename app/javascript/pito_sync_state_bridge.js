// pito_sync_state_bridge — single global subscription to the
// `pito:sync_state` cable channel.
//
// 2026-05-25 (sync-rebuild) — the canonical client-side bridge from
// the server's sync-state cable broadcasts to the existing
// `tui:sync-changed` document event that every per-target sync VC
// controller already listens for. ONE subscription per page (the
// browser ConnectionMonitor reconnects on disconnect); per-envelope
// fan-out via the document event.
//
// Wire shape (from `Pito::CableBroadcaster.broadcast_sync_state`):
//
//   { kind: "sync_state",
//     payload: { target: "home.stack.meilisearch", enabled: true },
//     ts: "..." }
//
// Side effects:
//
//   - Caches `enabled` per target on `window.__pitoSyncStateCache`
//     so the per-VC controllers can re-aggregate mixed-state on
//     parent panels without a server round-trip.
//   - Dispatches `tui:sync-changed` with detail
//     `{ target, parentTarget: null, enabled }` so every VC repaints.
//
// Import-for-side-effect from `application.js`; do NOT export the
// subscription handle.
import { createConsumer } from "@rails/actioncable"

const SUBSCRIBED_FLAG = "__pitoSyncStateBridgeSubscribed"

function applyBroadcast(envelope) {
  if (!envelope) return
  const payload = envelope.payload || {}
  const target = payload.target
  const enabled = payload.enabled
  if (typeof target !== "string" || target.length === 0) return
  if (typeof enabled !== "boolean") return
  // Mirror cache used by tui_sync_indicator_controller for fast
  // parent-mixed derivation. Idempotent.
  window.__pitoSyncStateCache = window.__pitoSyncStateCache || {}
  window.__pitoSyncStateCache[target] = enabled
  document.dispatchEvent(new CustomEvent("tui:sync-changed", {
    detail: { target, parentTarget: null, enabled }
  }))
}

function subscribeOnce() {
  if (window[SUBSCRIBED_FLAG]) return
  window[SUBSCRIBED_FLAG] = true
  const consumer = createConsumer()
  consumer.subscriptions.create(
    { channel: "Pito::SyncStateChannel" },
    {
      received: (data) => applyBroadcast(data)
    }
  )
}

// Subscribe as soon as the document is parsed. Turbo Drive keeps the
// page alive across navigations, so the subscription survives without
// needing a `turbo:load` re-bind.
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", subscribeOnce, { once: true })
} else {
  subscribeOnce()
}
