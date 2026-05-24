import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { isTargetSyncDisabled } from "controllers/tui_sync_indicator_controller"

/**
 * tui-panel-cable — per-panel cable subscriber. Mounted on every
 * Pito::*PanelComponent root via the Tui::PanelBase mixin's
 * `panel_root_data` helper.
 *
 * Data attrs:
 *   data-tui-panel-cable-screen-value="home"
 *   data-tui-panel-cable-name-value="security"
 *
 * On connect, subscribes to Pito::PanelChannel with the screen+name params.
 * On received, dispatches `pito:panel:<name>:received` event on the panel
 * element with the cable kind/payload as event.detail. Panel-specific
 * Stimulus controllers listen for that event and update their VC slot.
 *
 * Lifecycle:
 *   connect    → create consumer + subscription
 *   connected  → emit `pito:panel:<name>:connected` (bubbles: false)
 *   received   → emit `pito:panel:<name>:received` with { kind, payload, ts }
 *   disconnected → emit `pito:panel:<name>:disconnected`
 *   disconnect → unsubscribe + tear down consumer
 *
 * Reconnects on disconnect via createConsumer's default reconnect policy.
 *
 * Sync suppression (Phase 1D, 2026-05-24):
 *   Before dispatching a received event, the controller checks the
 *   `pito.sync.<screen>.<name>` localStorage flag via
 *   `isTargetSyncDisabled()`. If disabled (direct flag = "no" or
 *   inherited from a parent panel target = "no"), the broadcast is
 *   dropped silently and no event fires. The semantic flipped from the
 *   prior `pito.pause.<target>` = "yes" suppress shape to the canonical
 *   `pito.sync.<target>` = "no" suppress shape — pausing = unchecked
 *   sync = disabled.
 *
 * Contract: see docs/architecture.md § Cable channel grammar
 */
export default class extends Controller {
  static values = {
    screen: String,
    name: String
  }

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "Pito::PanelChannel", screen: this.screenValue, name: this.nameValue },
      {
        connected: () => this.onConnected(),
        disconnected: () => this.onDisconnected(),
        received: (data) => this.onReceived(data)
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
  }

  onConnected() {
    this.element.dispatchEvent(
      new CustomEvent(`pito:panel:${this.nameValue}:connected`, { bubbles: false })
    )
  }

  onDisconnected() {
    this.element.dispatchEvent(
      new CustomEvent(`pito:panel:${this.nameValue}:disconnected`, { bubbles: false })
    )
  }

  onReceived(data) {
    const { kind, payload, ts } = data || {}
    // Phase 1D (2026-05-24) — drop the payload silently if the target's
    // sync is disabled via localStorage. Target = `<screen>.<name>`
    // matching Tui::SyncIndicatorComponent's localStorage key suffix.
    const target = `${this.screenValue}.${this.nameValue}`
    if (isTargetSyncDisabled(target)) return
    this.element.dispatchEvent(
      new CustomEvent(`pito:panel:${this.nameValue}:received`, {
        detail: { kind, payload, ts },
        bubbles: false
      })
    )
  }
}
