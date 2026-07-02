# frozen_string_literal: true

# Pure FAN-OUT for a turn's pending `analyze` messages: per pending analyze
# event, enqueue one AnalyzeMetricJob per metric — each folds its own data from
# the shared primitives layer and swaps its own cell. The message owns the fan
# + the barrier; the last metric to land composes the persisted ready state
# FROM THE PER-METRIC STASHES (AnalyzeMetricJob#ready_data — 0.9.0 Phase 4),
# resolves that message's indicator, and completes the turn. A pending event
# with no metric_keys resolves immediately so the turn never hangs.
#
# The old in-job aggregate path (compute + chart helpers re-fetching every
# metric at finalize, plus scaffold probes across all reports at the message
# window) was removed in 0.9.0 Phase 4 — AnalyzeMetricFill is the single
# per-metric compute path now.
class AnalyzePrepareJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    fanned      = 0

    pending_events(turn).each do |event|
      keys = event.payload.dig("analyze", "metric_keys")
      if keys.blank?
        broadcaster.resolve_thinking_for(turn:, message_id: event.id)
        next
      end

      keys.each { |key| AnalyzeMetricJob.perform_later(event.id, key) }
      fanned += keys.size
    end

    broadcaster.complete_turn(turn:) if fanned.zero? && broadcaster.all_thinking_resolved?(turn:)
  end

  private

  def pending_events(turn)
    turn.events.select { |e| Pito::MessageBuilder::Analyze::Message.pending?(e) }
  end
end
