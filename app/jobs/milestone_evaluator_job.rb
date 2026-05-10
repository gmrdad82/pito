# Phase 15 §1 — Calendar Data Model.
#
# Sidekiq cron entry: daily at 02:00 UTC. Triggered manually by the
# analytics sync (Phase 13) when a metric snapshot lands; runs as a
# daily fallback regardless.
class MilestoneEvaluatorJob < ApplicationJob
  queue_as :default

  def perform
    Calendar::MilestoneEvaluator.new.evaluate_all!
  end
end
