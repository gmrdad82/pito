class SettingsController < ApplicationController
  # C19e (2026-05-22) — orphan trim. SettingsController#index was
  # unreachable after C18 (GET /settings → 301 redirect to /). All ivar
  # setup, session-sort helpers, and probe helpers have been removed.
  #
  # Remaining routed actions:
  #   PATCH  /settings               → update  (legacy passthrough; redirect)
  #   POST   /settings/stack/meilisearch/reindex → meilisearch_reindex
  #   POST   /settings/stack/voyage/reindex      → voyage_reindex
  #   GET    /settings/stack_stats               → stack_stats (JSON diagnostics)

  # Phase 29 (settings refactor) — legacy passthrough. The multi-section
  # dispatcher is gone. Scripted PATCH callers still hitting `/settings`
  # get a clean redirect + notice — no 500s, no silent writes.
  def update
    redirect_to settings_path, notice: t("settings.flash.saved")
  end

  # 2026-05-18 (DR follow-up) — KEPT as a fallback / diagnostics
  # endpoint after the live `/settings` pane moved from HTTP polling to
  # ActionCable push (see `StackStatsChannel` + `StackStats::Broadcaster`).
  # The Stimulus controller no longer hits this URL on a timer, but
  # leaving the route + action live is cheap and useful for one-shot
  # `curl /settings/stack_stats` debugging and any future automation
  # that wants a synchronous snapshot.
  #
  # Both this action and the cable broadcaster call the same shared
  # builder (`StackStats::Payload`) so the wire shape is identical
  # regardless of transport.
  def stack_stats
    render json: StackStats::Payload.call
  rescue StandardError => e
    Rails.logger.warn("[settings#stack_stats] #{e.class}: #{e.message}")
    render json: { redis: {}, voyage: {}, postgres: {}, meilisearch: {}, assets: {} }, status: :ok
  end

  # FB-63 (2026-05-20) — split reindex actions. The combined
  # `[reindex]` action is gone; each subsystem tile now owns its own
  # `[reindex]` link.
  #
  # FB-138 (2026-05-21). Returns `head :no_content` (HTTP 204) so Turbo
  # does nothing on success — the cable broadcast drives the in-place UI
  # swap. FB-149: conflicts also return 204.
  def meilisearch_reindex
    unless AppSetting.reindex_running?
      AppSetting.start_reindex!
      MeilisearchReindexJob.perform_later
    end
    head :no_content
  end

  def voyage_reindex
    unless AppSetting.reindex_running?
      AppSetting.start_reindex!
      VoyageReindexJob.perform_later
    end
    head :no_content
  end
end
