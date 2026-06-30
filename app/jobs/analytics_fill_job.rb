# frozen_string_literal: true

# Fans out a glance turn's analytics work. `show video` / `show game` / `show
# channel` emit an :enhanced glance INSTANTLY with a pending marker (intro + a
# loading skeleton of all metric cells); the Finalizer enqueues this job and defers
# resolving those messages' indicators + completing the turn.
#
# This job does NO fetching. Its sole job is the fan-out: for each pending glance
# event it enqueues ONE AnalyticsMetricJob per metric. Each metric then makes its
# OWN dedicated YouTube request and swaps its OWN cell, fault-isolated — so one
# metric failing never sinks the rest. The message owns fan + aggregate (the
# barrier): the last metric to land per event resolves that message's indicator
# and, when every indicator in the turn is resolved, completes the turn
# (AnalyticsMetricJob#finalize).
class AnalyticsFillJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    fanned      = 0

    turn.events.where(kind: :enhanced).find_each do |event|
      next unless Pito::MessageBuilder::Analytics::Enhanced.pending?(event)

      keys = event.payload.dig("analytics", "metric_keys")
      if keys.blank?
        # No metrics to fan — resolve this message's indicator now so the turn can
        # still complete (no metric job will do it for this event).
        broadcaster.resolve_thinking_for(turn:, message_id: event.id)
        next
      end

      keys.each { |key| AnalyticsMetricJob.perform_later(event.id, key) }
      fanned += keys.size
    end

    # If nothing was fanned anywhere, complete here so the turn never hangs; with
    # metrics fanned, the last AnalyticsMetricJob completes the turn instead.
    broadcaster.complete_turn(turn:) if fanned.zero? && broadcaster.all_thinking_resolved?(turn:)
  end
end
