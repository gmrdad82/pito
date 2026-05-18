import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// 2026-05-18 (DR follow-up) — Live updates for the /settings Stack pane.
//
// User direction (verbatim): "no polling, have all the jobs publishing
// on websocket / action cable / magically".
//
// Architecture: this controller subscribes to `StackStatsChannel`
// (broadcasting `stack_stats`). Sidekiq jobs at the producer side
// (`BulkVoyageIndexJob`, `GameVoyageIndexJob`, `BundleVoyageIndexJob`,
// `ReindexAllJob`) call `StackStats::Broadcaster.broadcast!` in their
// ensure blocks, which pushes the same payload the old JSON endpoint
// returned. The wire shape is identical — only the transport changed
// (HTTP poll → WebSocket push) — so every `updateXxx` helper below is
// unchanged.
//
// Initial state comes from the server-rendered ERB (already there);
// no fetch() on connect. The JSON endpoint at `/settings/stack_stats`
// stays live as a fallback / diagnostics surface but is not called by
// this controller.
//
// Targets are the individual numeric cells in `_stack_pane.html.erb`
// + `_voyage_section.html.erb`. Each `hasXxxTarget` guard keeps the
// controller resilient to partial markup (e.g. when only Voyage cells
// exist on a future variant of the pane).
export default class extends Controller {
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
    "voyageBundlesCoveragePct",
    "voyagePct",
    "voyageLast",
    "voyageStorage",
    "voyage24h",
    // Postgres per-row breakdown (games / bundles)
    "postgresGamesRows",
    "postgresGamesSize",
    "postgresBundlesRows",
    "postgresBundlesSize",
    // Meilisearch per-row breakdown (games / bundles inside the unified
    // `games_<env>` index). The bundles row's size cell is intentionally
    // omitted server-side (rendered as "—") so no live target exists for it.
    "meilisearchGamesDocs",
    "meilisearchGamesSize",
    "meilisearchBundlesDocs",
    "meilisearchBundlesSize",
    // Assets per-row breakdown (cover arts + composites). "cover arts"
    // collapses to a single camelCase target name (`CoverArts`).
    "assetsCoverArtsFiles",
    "assetsCoverArtsSize",
    "assetsCompositesFiles",
    "assetsCompositesSize"
  ]

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "StackStatsChannel" },
      { received: (data) => this.applyPayload(data) }
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

  applyPayload(data) {
    if (!data) return
    if (data.redis) this.updateRedis(data.redis)
    if (data.voyage) this.updateVoyage(data.voyage)
    if (data.postgres) this.updatePostgres(data.postgres)
    if (data.meilisearch) this.updateMeilisearch(data.meilisearch)
    if (data.assets) this.updateAssets(data.assets)
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
    // 2026-05-18 — `bundle_coverage_pct` is nil-safe: returns null when
    // the `bundles.summary_embedding` column is absent. Skip the write so
    // the cell stays untouched (the ERB `if` guard hides the parenthetical
    // entirely in that case).
    if (
      this.hasVoyageBundlesCoveragePctTarget &&
      voyage.bundle_coverage_pct !== undefined &&
      voyage.bundle_coverage_pct !== null
    ) {
      this.voyageBundlesCoveragePctTarget.textContent = voyage.bundle_coverage_pct
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

  // 2026-05-18 — per-row Postgres updater. Payload shape (flat keys):
  //   { games_rows, games_size_bytes, bundles_rows, bundles_size_bytes }
  updatePostgres(postgres) {
    this.setDelimited(this.hasPostgresGamesRowsTarget && this.postgresGamesRowsTarget, postgres.games_rows)
    this.setFilesize(this.hasPostgresGamesSizeTarget && this.postgresGamesSizeTarget, postgres.games_size_bytes)
    this.setDelimited(this.hasPostgresBundlesRowsTarget && this.postgresBundlesRowsTarget, postgres.bundles_rows)
    this.setFilesize(this.hasPostgresBundlesSizeTarget && this.postgresBundlesSizeTarget, postgres.bundles_size_bytes)
  }

  // 2026-05-18 — per-row Meilisearch updater. Payload shape (flat keys):
  //   { games_docs, games_size_bytes, bundles_docs, bundles_size_bytes }
  // The bundles row's size cell is intentionally rendered server-side as
  // a static "—" (no live target); only the doc count is live-patched.
  updateMeilisearch(meilisearch) {
    this.setDelimited(this.hasMeilisearchGamesDocsTarget && this.meilisearchGamesDocsTarget, meilisearch.games_docs)
    this.setFilesize(this.hasMeilisearchGamesSizeTarget && this.meilisearchGamesSizeTarget, meilisearch.games_size_bytes)
    this.setDelimited(this.hasMeilisearchBundlesDocsTarget && this.meilisearchBundlesDocsTarget, meilisearch.bundles_docs)
    this.setFilesize(this.hasMeilisearchBundlesSizeTarget && this.meilisearchBundlesSizeTarget, meilisearch.bundles_size_bytes)
  }

  // 2026-05-18 — per-row assets updater. Payload shape (flat keys):
  //   { cover_arts_files, cover_arts_size_bytes,
  //     composites_files, composites_size_bytes }
  updateAssets(assets) {
    this.setDelimited(this.hasAssetsCoverArtsFilesTarget && this.assetsCoverArtsFilesTarget, assets.cover_arts_files)
    this.setFilesize(this.hasAssetsCoverArtsSizeTarget && this.assetsCoverArtsSizeTarget, assets.cover_arts_size_bytes)
    this.setDelimited(this.hasAssetsCompositesFilesTarget && this.assetsCompositesFilesTarget, assets.composites_files)
    this.setFilesize(this.hasAssetsCompositesSizeTarget && this.assetsCompositesSizeTarget, assets.composites_size_bytes)
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

  // 2026-05-18 — mirror of `human_filesize_int` (KB-minimum integer
  // output, matching the helper used by the initial ERB render). Used
  // by the Postgres / Meilisearch / assets size cells so the live
  // refresh doesn't flip the formatting to a raw byte count. Falls back
  // to "—" on nil so the cell stays consistent with the server render.
  setFilesize(target, bytes) {
    if (!target) return
    if (bytes === undefined || bytes === null) {
      target.textContent = "—"
      return
    }
    const numeric = Number(bytes)
    if (!Number.isFinite(numeric) || numeric <= 0) {
      target.textContent = "0 KB"
      return
    }
    const units = ["KB", "MB", "GB", "TB"]
    let value = numeric / 1024
    let unit = "KB"
    for (let i = 0; i < units.length; i += 1) {
      unit = units[i]
      if (value < 1024 || i === units.length - 1) break
      value = value / 1024
    }
    const rounded = Math.round(value)
    target.textContent = `${rounded.toLocaleString()} ${unit}`
  }
}
