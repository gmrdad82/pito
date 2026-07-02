# frozen_string_literal: true

# Fills ONE metric cell of an analyze :system/:enhanced message by folding from
# the shared primitives layer (Pito::Analytics::AnalyzeMetricFill), then swaps
# just that cell into the live message. Fanned out — one job per metric — by
# AnalyzePrepareJob, so each metric arrives independently and one failing never
# blocks the rest (its cell shows the NoData placeholder; the others still fill).
#
# Barrier (0.9.0 Phase 4 — the stash pattern, mirroring the glance's
# AnalyticsMetricJob): each job records its metric done AND stashes its RAW
# ingredient ({slot, data}) on the event (row-locked). The LAST metric to land
# composes the persisted ready state from the stashes via
# Message#ready_payload — NO re-aggregate, NO refetch, NO scaffold probe
# requests (the old finalize re-ran AnalyzePrepareJob.aggregate over every
# metric, refetching and probing all reports at the message window). It then
# resolves THIS message's thinking indicator and completes the turn once every
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

    filled = Pito::Analytics::AnalyzeMetricFill.for(
      metric:, level: marker["level"], entity_ids: marker["entity_ids"], period: marker["period"]
    )
    swap_cell(broadcaster, token:, metric:, cell: filled.cell)
    finalize(event, broadcaster, metric:, raw: filled.raw)
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

  # Record this metric done; the last metric to land composes the ready message
  # from the stashes, resolves the indicator, and completes the turn when
  # everything is resolved.
  def finalize(event, broadcaster, metric:, raw:)
    turn      = event.turn
    completed = mark_done(event, metric:, raw:)
    return unless completed

    broadcaster.replace_event(event)
    broadcaster.resolve_thinking_for(turn:, message_id: event.id)
    broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
  end

  # Row-locked: append `metric` to metrics_done, stash its raw ingredient, and —
  # once every metric_key is done — rewrite the event to its ready state from
  # the stashes. Returns true only for the last metric.
  def mark_done(event, metric:, raw:)
    event.with_lock do
      event.reload
      marker = event.payload["analyze"]
      return false unless marker && marker["status"] == "pending"

      done  = ((marker["metrics_done"] || []) + [ metric.to_s ]).uniq
      stash = marker["stash"] || {}
      stash = stash.merge(metric.to_s => raw) unless raw.nil?
      all   = ((marker["metric_keys"] || []) - done).empty?

      payload =
        if all
          data = ready_data(marker.merge("stash" => stash))
          Pito::MessageBuilder::Analyze::Message.ready_payload(event, data:)
        else
          event.payload.merge("analyze" => marker.merge("metrics_done" => done, "stash" => stash))
        end
      event.update!(payload:)
      all
    end
  end

  # Compose Message#ready_payload's data Hash from the per-metric stashes —
  # the jsonb round-trip stores string keys; charts/bars re-key to symbols and
  # the likes hearts re-symbolize (likes_marker reads h[:score] etc.).
  # Scaffold semantics ("metric => data-pulled?") derive from stash presence —
  # a metric stashed raw data iff its fill found data.
  def ready_data(marker)
    stash  = marker["stash"] || {}
    charts = {}
    bars   = {}
    likes  = nil

    stash.each do |metric, entry|
      case entry["slot"]
      when "charts" then charts[metric.to_sym] = entry["data"]
      when "bars"   then bars[metric.to_sym]   = entry["data"]
      when "likes"  then likes = Array(entry["data"]).map { |h| h.symbolize_keys }
      end
    end

    scaffold = Array(marker["metric_keys"]).index_with { |m| stash.key?(m) }.transform_keys(&:to_sym)
    { scaffold:, charts:, likes:, bars: }
  end
end
