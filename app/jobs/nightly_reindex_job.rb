# frozen_string_literal: true

# Stage 2 master: nightly reindex orchestrator, scheduled at 2:00 UTC.
#
# Runs ≥1h after Stage 1 (`NightlySyncJob` at 1:00 UTC) so freshly synced
# games and videos have time to land before we check/queue their embeddings.
# Separate cron entries (NOT a delayed enqueue from Stage 1) so a long sync
# backlog can never compress the gap.
#
# Fan-out strategy — atomic-jobs principle:
#
#   - `GameVoyageIndexJob.perform_later(id)` per game
#   - `VideoVoyageIndexJob.perform_later(id)` per video
#
# Both indexers are digest-gated (`Game::VoyageIndexer` /
# `Video::VoyageIndexer`): unchanged rows are no-ops so the nightly cost
# is only the actually-changed records. `BulkVoyageIndexJob` is left for
# manual operator full-reindex runs; this master uses per-entity fan-out
# per the atomic-jobs locked decision.
#
# Design B (locked): channels have NO embedding of their own. Channel↔game
# recommendations are computed on demand from video vectors. There is NO
# channel-centroid step here.
#
# Scheduled via config/recurring.yml at "0 2 * * *" (UTC).
class NightlyReindexJob < ApplicationJob
  queue_as :default

  def perform
    ::Game.find_each do |game|
      ::GameVoyageIndexJob.perform_later(game.id)
    end

    ::Video.find_each do |video|
      ::VideoVoyageIndexJob.perform_later(video.id)
    end
  end
end
