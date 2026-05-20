import { Controller } from "@hotwired/stimulus";
import { createConsumer } from "@rails/actioncable";

// FB-126 (2026-05-21). Toggles a Stack-pane sub-panel action between
// `[reindex]` (idle) and `Tui::ReindexProgressComponent` (running) based
// on cable broadcasts on the shared `stack_stats` channel.
//
// Wire shape (two distinct broadcast forms on the same channel):
//
//   * Brand-tagged START event, emitted by the job at the very top of
//     `#perform` BEFORE work begins:
//
//       { reindex_event: { kind: "reindex_started", brand: "meilisearch" } }
//
//     Only the matching brand flips. The other brand stays idle.
//
//   * Snapshot broadcast (`StackStats::Broadcaster.broadcast!`), emitted
//     in the job's `ensure` block AFTER work completes. Shape includes
//     a `reindex.running` boolean on the standard payload:
//
//       { redis: …, voyage: …, …, reindex: { running: false } }
//
//     When `reindex.running` is `false`, ALL controllers flip back to
//     idle (single shared lock — only one job can be in flight at a
//     time, so this is safe).
//
// The controller owns its own ActionCable subscription so the toggle
// works even when the page wasn't mounted with the
// `stack-stats-live` controller (e.g. the future Stack screen variants).
export default class extends Controller {
  static values = { brand: String };
  static targets = ["idle", "running"];

  connect() {
    this.consumer = createConsumer();
    this.subscription = this.consumer.subscriptions.create(
      { channel: "StackStatsChannel" },
      { received: (data) => this.applyPayload(data) }
    );
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
    if (this.consumer) {
      this.consumer.disconnect();
      this.consumer = null;
    }
  }

  applyPayload(data) {
    if (!data) return;
    if (data.reindex_event) {
      this.handleEvent(data.reindex_event);
      return;
    }
    if (data.reindex && typeof data.reindex.running !== "undefined") {
      this.setRunning(Boolean(data.reindex.running) && this.brandMatches(data.reindex.brand));
    }
  }

  handleEvent(event) {
    if (event.kind === "reindex_started" && this.brandMatches(event.brand)) {
      this.setRunning(true);
    } else if (event.kind === "reindex_completed") {
      this.setRunning(false);
    }
  }

  // Snapshot broadcasts carry no brand; treat any nil brand as
  // "applies to whichever brand was running" (the lock is shared, so a
  // `running: false` snapshot universally flips both back to idle).
  brandMatches(brand) {
    if (!brand) return true;
    return brand === this.brandValue;
  }

  setRunning(running) {
    if (this.hasIdleTarget) this.idleTarget.hidden = running;
    if (this.hasRunningTarget) this.runningTarget.hidden = !running;
  }
}
