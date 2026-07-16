# frozen_string_literal: true

# Run-once-on-deploy trigger for the similar-game `:strip` cover variant size
# bump (Game#cover_art — 360×480 → 432×576, 2026-07-16). `pito update` runs
# `bin/rails db:prepare` in `bin/docker-entrypoint`, which applies pending
# migrations exactly once per deploy; enqueuing here just persists a
# SolidQueue row that workers process in the background after boot. Because
# migrations are versioned (recorded in schema_migrations), this can never
# fire twice. See app/jobs/strip_cover_regeneration_job.rb for the backfill
# itself (idempotent).
class EnqueueStripCoverRegeneration < ActiveRecord::Migration[8.1]
  def up
    StripCoverRegenerationJob.perform_later
  end

  def down
    # No-op: an enqueue has no schema to reverse.
  end
end
