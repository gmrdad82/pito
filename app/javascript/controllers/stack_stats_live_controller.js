import { Controller } from "@hotwired/stimulus"

// 2026-05-18 (DR) — Live updates for the /settings Stack pane.
//
// User direction (verbatim): "[reindex] on Voyage AI for sure it queued
// a Sidekiq job so the Redis in stack should account for this and
// updates it's numbers. Sidekiq jobs should send through websocket /
// action cable / whatever magic way pings so if I'm on the /settings
// page the Redis stack gets updated."
//
// Implementation choice: simple polling (no ActionCable). Solo-user
// scale + tiny payload + 3 s cadence keeps the cost negligible.
// Stimulus `disconnect()` clears the interval when the user navigates
// away — Turbo's drive triggers it on every page transition.
//
// Targets are the individual numeric cells in `_stack_pane.html.erb`
// + `_voyage_section.html.erb`. Each `hasXxxTarget` guard keeps the
// controller resilient to partial markup (e.g. when only Voyage cells
// exist on a future variant of the pane).
export default class extends Controller {
  static values = {
    intervalMs: { type: Number, default: 3000 },
    url: { type: String, default: "/settings/stack_stats" }
  }

  static targets = [
    // Sidekiq / Redis counters
    "busy",
    "scheduled",
    "enqueued",
    "retry",
    "dead",
    "successful",
    "failed",
    // Voyage embedding stats
    "voyageEmbedded",
    "voyageTotal",
    "voyageBundlesEmbedded",
    "voyageBundlesTotal",
    "voyagePct",
    "voyageLast",
    "voyageStorage",
    "voyage24h"
  ]

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalMsValue)
  }

  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) return
      const data = await response.json()
      if (data.redis) this.updateRedis(data.redis)
      if (data.voyage) this.updateVoyage(data.voyage)
    } catch (_e) {
      // Swallow — the next interval tick retries. A persistent network
      // failure surfaces nowhere noisy; users get stale numbers, not
      // a broken UI.
    }
  }

  updateRedis(redis) {
    this.setNumber(this.hasBusyTarget && this.busyTarget, redis.busy)
    this.setNumber(this.hasScheduledTarget && this.scheduledTarget, redis.scheduled)
    this.setNumber(this.hasEnqueuedTarget && this.enqueuedTarget, redis.enqueued)
    this.setNumber(this.hasRetryTarget && this.retryTarget, redis.retry)
    this.setNumber(this.hasDeadTarget && this.deadTarget, redis.dead)
    this.setDelimited(this.hasSuccessfulTarget && this.successfulTarget, redis.processed)
    this.setDelimited(this.hasFailedTarget && this.failedTarget, redis.failed)
  }

  updateVoyage(voyage) {
    this.setDelimited(this.hasVoyageEmbeddedTarget && this.voyageEmbeddedTarget, voyage.embedded_games_count)
    this.setDelimited(this.hasVoyageTotalTarget && this.voyageTotalTarget, voyage.total_games_count)
    // 2026-05-18 (follow-up) — Bundle coverage cells. Both keys come
    // back as `null` when the `bundles.summary_embedding` column is
    // absent (see `Voyage::Stats#bundle_embedding_supported?`); the
    // `setDelimited` helper short-circuits on null so the existing
    // cell text (or absent ERB span) is left alone.
    this.setDelimited(this.hasVoyageBundlesEmbeddedTarget && this.voyageBundlesEmbeddedTarget, voyage.embedded_bundles_count)
    this.setDelimited(this.hasVoyageBundlesTotalTarget && this.voyageBundlesTotalTarget, voyage.total_bundles_count)
    if (this.hasVoyagePctTarget && voyage.coverage_pct !== undefined && voyage.coverage_pct !== null) {
      this.voyagePctTarget.textContent = voyage.coverage_pct
    }
    if (this.hasVoyageLastTarget && voyage.last_indexed_at_formatted) {
      this.voyageLastTarget.textContent = voyage.last_indexed_at_formatted
    }
    // 2026-05-18 (follow-up) — `storage_kb` may be `null` when the
    // pg_indexes query failed; skip the assignment so the cell keeps its
    // last good value (or stays hidden via the ERB guard).
    this.setDelimited(this.hasVoyageStorageTarget && this.voyageStorageTarget, voyage.storage_kb)
    this.setDelimited(this.hasVoyage24hTarget && this.voyage24hTarget, voyage.embeddings_last_24h)
  }

  // Helpers — gated on a truthy target (the `hasXTarget && this.xTarget`
  // pattern short-circuits to `false` when the target is absent, so
  // these helpers no-op rather than throw).
  setNumber(target, value) {
    if (!target || value === undefined || value === null) return
    target.textContent = value
  }

  setDelimited(target, value) {
    if (!target || value === undefined || value === null) return
    target.textContent = Number(value).toLocaleString()
  }
}
