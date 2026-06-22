# frozen_string_literal: true

# Fills the analytics :enhanced message(s) for a turn, then resolves the turn.
#
# `show video` / `show game` emit an analytics :enhanced event INSTANTLY with a
# pending marker (intro only); the Finalizer enqueues this job and defers
# resolving THAT message's per-message thinking indicator + completing the turn
# to here. So the analytics card's own spinner stays up until the data lands,
# while any plain messages in the same turn already resolved their indicators.
#
# For each analytics event: fetch the scalars for its scope+period, rewrite the
# payload to the ready (intro + kv-table) state — PERSISTED so a mid-job refresh
# still shows spinner+intro and a post-job refresh shows the data — broadcast a
# replace so an open page updates live, then resolve THAT message's own indicator
# (by `for_event_id`, never `.last`). The turn completes in an `ensure`, but only
# once every indicator is resolved, so the dots never hide while one still spins.
class AnalyticsFillJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    begin
      turn.events.where(kind: :enhanced).find_each do |event|
        next unless analytics_event?(event)

        # Fill the pending data (idempotent on retry — already-ready events skip
        # the fetch but still get their indicator resolved below).
        fill(event, broadcaster) if Pito::MessageBuilder::Analytics::Enhanced.pending?(event)

        # Resolve THIS message's own indicator (not `.last`) so a turn mixing a
        # pending-analytics card with plain messages resolves each independently.
        broadcaster.resolve_thinking_for(turn:, message_id: event.id)
      end
    ensure
      # Complete only once EVERY indicator in the turn is resolved — the ready
      # messages were resolved by the Finalizer, the analytics ones just above —
      # so the dots never vanish while another indicator is still spinning.
      broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
    end
  end

  private

  def fill(event, broadcaster)
    marker = event.payload["analytics"]
    scope  = resolve_scope(marker["scope_type"], marker["scope_id"])
    result = scope ? Pito::Analytics::Scalars.for(scope: scope, period: marker["period"]) : Pito::Analytics::Scalars::UNAVAILABLE

    write_ready(event, broadcaster, scope:, period: marker["period"], result:, intro: marker["intro"])
  rescue StandardError => e
    Rails.logger.warn("[AnalyticsFillJob] event ##{event.id}: #{e.class}: #{e.message}")
    write_ready(event, broadcaster, scope: nil, period: marker&.dig("period"), result: Pito::Analytics::Scalars::UNAVAILABLE, intro: marker&.dig("intro"))
  end

  def write_ready(event, broadcaster, scope:, period:, result:, intro:)
    event.update!(
      payload: Pito::MessageBuilder::Analytics::Enhanced.ready_payload(scope:, period:, result:, intro:)
    )
    broadcaster.replace_event(event)
  end

  def resolve_scope(type, id)
    return nil unless %w[Video Game Channel].include?(type.to_s)

    type.constantize.find_by(id: id)
  end

  # True for any enhanced event carrying an analytics marker (pending OR already
  # filled). Used so a retry still resolves an indicator whose event was filled
  # but whose resolve didn't land on the previous attempt.
  def analytics_event?(event)
    event.payload.is_a?(Hash) && event.payload["analytics"].present?
  end
end
