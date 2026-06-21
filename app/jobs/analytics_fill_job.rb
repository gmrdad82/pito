# frozen_string_literal: true

# Fills the analytics :enhanced message(s) for a turn, then resolves the turn.
#
# `show video` / `show game` emit an analytics :enhanced event INSTANTLY with a
# pending marker (intro only); ChatDispatchJob enqueues this job and defers
# resolving the thinking indicator + completing the turn to here. So the
# cycling "thinking…" spinner stays up until the data has actually landed.
#
# For each pending analytics event: fetch the scalars for its scope+period,
# rewrite the payload to the ready (intro + kv-table) state — PERSISTED so a
# mid-job refresh still shows spinner+intro and a post-job refresh shows the
# data — and broadcast a replace so an open page updates live. The
# resolve+complete run in an `ensure`, so the spinner always resolves even if a
# fetch fails.
class AnalyticsFillJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    begin
      turn.events.where(kind: :enhanced).find_each do |event|
        next unless Pito::MessageBuilder::Analytics::Enhanced.pending?(event)

        fill(event, broadcaster)
      end
    ensure
      broadcaster.resolve_thinking(turn:)
      broadcaster.complete_turn(turn:)
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
end
