import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

/**
 * tui-panel-cable — per-panel cable subscriber. Mounted on every
 * Pito::*PanelComponent root via the Tui::PanelBase mixin's
 * `panel_root_data` helper.
 *
 * Data attrs:
 *   data-tui-panel-cable-screen-value="home"
 *   data-tui-panel-cable-name-value="security"
 *
 * On connect, subscribes to Pito::PanelChannel with the screen+name
 * params. On received, dispatches `pito:panel:<name>:received` event
 * on the panel element with the cable kind/payload as event.detail.
 * Panel-specific Stimulus controllers listen for that event and
 * update their VC slot.
 *
 * Lifecycle:
 *   connect      → create consumer + subscription
 *   connected    → emit `pito:panel:<name>:connected` (bubbles: false)
 *   received     → emit `pito:panel:<name>:received` with envelope
 *   disconnected → emit `pito:panel:<name>:disconnected`
 *   disconnect   → unsubscribe + tear down consumer
 *
 * Reconnects on disconnect via createConsumer's default reconnect policy.
 *
 * 2026-05-25 (sync-rebuild) — the client-side sync-suppression layer
 * (`isTargetSyncDisabled` reading `localStorage`) has been DELETED.
 * The server-side `Pito::CableBroadcaster` is now the single gate —
 * disabled targets never reach this controller at all. Removing the
 * client-side check eliminates the source of every drift bug where
 * the server and the localStorage layer disagreed about state.
 *
 * @contract see docs/architecture.md § Cable channel grammar
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
    this.element.dispatchEvent(
      new CustomEvent(`pito:panel:${this.nameValue}:received`, {
        detail: { kind, payload, ts },
        bubbles: false
      })
    )
  }
}
