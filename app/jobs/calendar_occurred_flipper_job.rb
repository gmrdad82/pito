# Phase 15 §1 — Calendar Data Model.
#
# Sidekiq cron entry: every hour at minute 5. Flips ripe scheduled
# entries to occurred.
class CalendarOccurredFlipperJob < ApplicationJob
  queue_as :default

  def perform
    Calendar::OccurredFlipper.flip_ripe!
  end
end
