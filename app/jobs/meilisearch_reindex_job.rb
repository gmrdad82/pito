# FB-63 (2026-05-20) — Meilisearch-only reindex job.
#
# Half of the split that replaced the combined `ReindexAllJob`. Where
# `VoyageReindexJob` (its sibling) re-embeds the Game + Bundle corpus
# through Voyage AI, this job repushes the SAME corpus into the unified
# `games_<env>` Meilisearch index. The two jobs are independently
# triggerable from the Stack pane — each subsystem tile owns its own
# `[reindex]` action so the operator can refresh Meilisearch documents
# without burning Voyage API budget (or vice versa).
#
# Three-layer lock contract (unchanged from `ReindexAllJob`):
#
#   Layer 1 — DB flag (`AppSetting.reindex_running` +
#             `reindex_started_at`). The controller
#             (`SettingsController#meilisearch_reindex`) consults the
#             flag BEFORE enqueueing; this job's `ensure` block clears
#             it so a worker crash never leaves it stuck.
#   Layer 2 — `sidekiq_options lock: :until_executed` (no-op intent in
#             Sidekiq OSS; enforced under sidekiq-unique-jobs /
#             Enterprise).
#   Layer 3 — UI gate. The Voyage section currently gates its own
#             render on the shared flag; that behaviour stays. The
#             Stack pane's per-tile `[reindex]` link is rendered idle
#             whenever the flag is clear and is hidden during a
#             running reindex. Both jobs broadcast the post-run
#             snapshot via `StackStats::Broadcaster` so any open
#             `/settings` tab catches the trailing edge.
#
# Why Meilisearch is its own job. The per-row Meilisearch push is a
# single HTTP call per document and Meilisearch does NOT rate-limit
# operator-driven batch upserts, so the simplest correct shape is a
# straight `find_each` over Game + Bundle that invokes the existing
# `Game::MeilisearchIndexer.call(game)` /
# `Bundle::MeilisearchIndexer.call(bundle)` service objects. Both
# services already swallow + log per-row failures, so a single bad
# document does not bomb the run.
class MeilisearchReindexJob < ApplicationJob
  queue_as :search
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    # FB-126 (2026-05-21) — emit a brand-tagged `reindex_started` event
    # on the shared `stack_stats` channel BEFORE the work begins so the
    # Meilisearch sub-panel flips from `[reindex]` to the
    # `Tui::ReindexProgressComponent` `[=------]` indicator immediately.
    # The `ensure` block then re-broadcasts the post-run snapshot via
    # `StackStats::Broadcaster.broadcast!` (which carries
    # `reindex.running: false`) so the indicator flips back to the
    # idle `[reindex]` action.
    ActionCable.server.broadcast("stack_stats", { reindex_event: { kind: "reindex_started", brand: "meilisearch" } })

    # ADR 0018 — panel-scoped cable broadcast. Tracks the
    # `pito:settings:stack:meilisearch` channel via the canonical
    # `Pito::CableBroadcaster` envelope (`kind:`, `payload:`, `ts:`) so
    # any panel subscriber (future progress bar, future indicator
    # variants) consumes a uniform shape. The legacy `stack_stats`
    # ActionCable broadcast above stays for back-compat until the cable
    # subscriber refactor.
    Pito::CableBroadcaster.broadcast_panel(
      "pito:settings:stack:meilisearch",
      kind: "reindex_event",
      payload: { state: "running" }
    )

    StackStats::Broadcaster.broadcast!

    Game.find_each do |game|
      Game::MeilisearchIndexer.call(game)
    end

    if defined?(Bundle) && Bundle.table_exists?
      Bundle.find_each do |bundle|
        Bundle::MeilisearchIndexer.call(bundle)
      end
    end
  ensure
    AppSetting.clear_reindex_lock!
    broadcast_voyage_section
    StackStats::Broadcaster.broadcast!
    Pito::CableBroadcaster.broadcast_panel(
      "pito:settings:stack:meilisearch",
      kind: "reindex_event",
      payload: { state: "complete" }
    )
    StackStatsBroadcastJob.set(wait: 1.second).perform_later
  end

  private

  # Re-render the Voyage section partial so the shared running/idle
  # state in `_voyage_section.html.erb` flips back to idle. The Voyage
  # tile shares the same lock flag — both panes show the running state
  # while either job is in flight, and both flip back together when
  # the flag clears in `ensure` above.
  def broadcast_voyage_section
    Turbo::StreamsChannel.broadcast_replace_to(
      "reindex_status",
      target: "voyage_section",
      partial: "settings/voyage_section"
    )
  rescue StandardError
    nil
  end
end
