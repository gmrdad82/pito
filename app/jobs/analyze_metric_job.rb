# frozen_string_literal: true

# Fills ONE metric cell of an analyze :system/:enhanced message via its OWN
# dedicated YouTube request (Pito::Analytics::AnalyzeMetricFill), then swaps just
# that cell into the live message. Fanned out — one job per metric — by
# AnalyzePrepareJob, so each metric arrives independently and one failing never
# blocks the rest (its cell shows the NoData placeholder; the others still fill).
#
# Barrier: each job records its metric done on the event (row-locked). The LAST
# metric to land rebuilds the message to its ready state — re-running the proven
# aggregate compute → Message#ready_payload, so the persisted body + the
# with/without mutate-reply behave exactly as before (quota is not a concern) —
# resolves THIS message's thinking indicator, and completes the turn once every
# indicator is resolved.
class AnalyzeMetricJob < ApplicationJob
  queue_as :default

  def perform(event_id, metric)
    event = Event.find_by(id: event_id)
    return unless event

    marker = event.payload["analyze"]
    return unless marker && marker["status"] == "pending"

    turn        = event.turn
    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    token       = marker["token"]

    cell = Pito::Analytics::AnalyzeMetricFill.for(
      metric:, level: marker["level"], entity_ids: marker["entity_ids"], period: marker["period"]
    )
    swap_cell(broadcaster, token:, metric:, cell:)
    finalize(event, broadcaster, metric:)
  end

  private

  # Render + broadcast just this metric's cell (filled, or its NoData placeholder).
  def swap_cell(broadcaster, token:, metric:, cell:)
    html = ApplicationController.renderer.render(
      Pito::Analytics::AnalyzeCellComponent.new(key: metric, token:, cell:),
      layout: false
    )
    broadcaster.replace_metric_fragment(token:, key: metric, html:)
  end

  # Record this metric done; the last metric to land rebuilds the ready message,
  # resolves the indicator, and completes the turn when everything is resolved.
  def finalize(event, broadcaster, metric:)
    turn      = event.turn
    completed = mark_done(event, metric:)
    return unless completed

    broadcaster.replace_event(event)
    broadcaster.resolve_thinking_for(turn:, message_id: event.id)
    broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
  end

  # Row-locked: append `metric` to metrics_done and, once every metric_key is done,
  # rewrite the event to its ready state. Returns true only for the last metric.
  def mark_done(event, metric:)
    event.with_lock do
      event.reload
      marker = event.payload["analyze"]
      return false unless marker && marker["status"] == "pending"

      done = ((marker["metrics_done"] || []) + [ metric.to_s ]).uniq
      all  = ((marker["metric_keys"] || []) - done).empty?

      payload =
        if all
          data = AnalyzePrepareJob.aggregate(marker)
          Pito::MessageBuilder::Analyze::Message.ready_payload(event, data:)
        else
          event.payload.merge("analyze" => marker.merge("metrics_done" => done))
        end
      event.update!(payload:)
      all
    end
  end
end
