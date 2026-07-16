# frozen_string_literal: true

# Retroactive backfill for the similar-game `:strip` cover variant size bump
# (Game#cover_art — see app/models/game.rb: 360×480 → 432×576, 2026-07-16).
# Without this job, each game's enlarged variant only gets (re)generated
# lazily on first view after a `pito update` — a one-time blur while
# ActiveStorage derives it from the master blob. Running this once
# pre-warms every game's `:strip` variant so the new size is ready
# immediately instead of blurring in per-game on first view.
#
# A separate, later deploy-time trigger enqueues this job exactly once after
# the size bump ships — this class is only the backfill itself.
#
# `cover_art.variant(:strip).processed` always derives from the master blob
# and is idempotent: already-current variants are a cheap no-op, so this job
# is safe to run repeatedly (e.g. re-triggered by mistake) and writes no DB
# rows of its own.
#
# == Error isolation
#
#   A StandardError rescue wraps each game's variant call so one game with a
#   missing/corrupt cover blob never aborts the backfill for the rest.
class StripCoverRegenerationJob < ApplicationJob
  queue_as :bulk_sync

  def perform
    ::Game.find_each do |game|
      regenerate_strip(game)
    end
  end

  private

  def regenerate_strip(game)
    return unless game.cover_art.attached?

    game.cover_art.variant(:strip).processed
  rescue StandardError => e
    Rails.logger.warn(
      "StripCoverRegenerationJob: failed for game=#{game.id}: " \
      "#{e.class}: #{e.message}"
    )
  end
end
