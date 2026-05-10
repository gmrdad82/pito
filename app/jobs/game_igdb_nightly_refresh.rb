# Phase 14 §1 — nightly Sidekiq cron job.
#
# Iterates `Game.synced.stale` (i.e., `igdb_synced_at < 7.days.ago`)
# and enqueues a `GameIgdbSync` per game, spaced ~300ms apart so the
# IGDB rate limit (4 req/s) is comfortably respected even before the
# in-process limiter engages.
#
# Never-synced games (`igdb_synced_at IS NULL`) are NOT enqueued —
# the only legitimate "never synced" state is the brief window
# between `add_from_igdb` and the immediate per-game sync triggered
# by the controller, which the nightly should not race against.
#
# Cron registration lives in `config/sidekiq_cron.yml`.
class GameIgdbNightlyRefresh
  include Sidekiq::Job
  sidekiq_options queue: :default

  def perform
    Game.synced.stale.find_each do |game|
      GameIgdbSync.perform_async(game.id)
      sleep 0.3
    end
  end
end
