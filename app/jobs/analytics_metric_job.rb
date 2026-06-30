# frozen_string_literal: true

# Fills ONE metric cell of a glance :enhanced message via its OWN dedicated YouTube
# request (Pito::Analytics::MetricFill), then swaps just that cell into the live
# message. Fanned out — one job per metric — by AnalyticsFillJob, so each metric
# arrives independently and one metric failing never blocks the rest (its cell
# shows an em dash; the others still fill).
#
# Barrier: each job records its key done on the event (row-locked). The LAST metric
# to land rewrites the message to its persisted ready state (so a refresh shows the
# data, not the skeleton), resolves THAT message's thinking indicator, and — once
# every indicator in the turn is resolved — completes the turn.
class AnalyticsMetricJob < ApplicationJob
  queue_as :default

  def perform(event_id, key)
    event  = Event.find_by(id: event_id)
    return unless event

    marker = event.payload["analytics"]
    return unless marker && marker["status"] == "pending"

    turn        = event.turn
    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    token       = marker["token"]
    scope       = resolve_scope(marker["scope_type"], marker["scope_id"])

    cell = scope ? Pito::Analytics::MetricFill.for(scope:, period: marker["period"], key:) : Pito::Analytics::MetricFill::UNAVAILABLE
    swap_cell(broadcaster, token:, key:, cell:)
    finalize(event, broadcaster, key:, cell:)
  end

  private

  # Render + broadcast just this metric's cell. We render the scalars table from a
  # single-metric Result (its other cells fall to em dashes) through the controller
  # renderer — which provides the view context the cell value-building needs — then
  # extract just this metric's `<token>__metric_<key>` cell node. A filled Cell
  # renders its sparkline + scalar; UNAVAILABLE renders from an empty Result
  # (correct label, em-dash value, no sparkline) so a failed metric reads as "no
  # data" rather than spinning forever. Reusing the table keeps ONE cell renderer.
  def swap_cell(broadcaster, token:, key:, cell:)
    result = cell == Pito::Analytics::MetricFill::UNAVAILABLE ? empty_result : cell.result
    series = cell == Pito::Analytics::MetricFill::UNAVAILABLE ? {}           : cell.series

    table_html = ApplicationController.renderer.render(
      Pito::Analytics::ScalarsTableComponent.new(result:, series:, token:),
      layout: false
    )
    node = Nokogiri::HTML5.fragment(table_html).at_css("[id='#{token}__metric_#{key}']")
    broadcaster.replace_metric_fragment(token:, key:, html: node.to_s) if node
  end

  # Record this metric done; the last metric to land persists the ready message,
  # resolves the indicator, and completes the turn when everything is resolved.
  def finalize(event, broadcaster, key:, cell:)
    turn      = event.turn
    completed = mark_done(event, key:, cell:)
    return unless completed

    broadcaster.replace_event(event)
    broadcaster.resolve_thinking_for(turn:, message_id: event.id)
    broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
  end

  # Row-locked: append `key` to metrics_done, stash its data, and — once every
  # metric_key is done — rewrite the event payload to its filled ready state.
  # Returns true only for the job that completed the last metric.
  def mark_done(event, key:, cell:)
    event.with_lock do
      event.reload
      marker = event.payload["analytics"]
      return false unless marker && marker["status"] == "pending"

      done  = ((marker["metrics_done"] || []) + [ key.to_s ]).uniq
      store = stash(marker, key, cell)
      all   = ((marker["metric_keys"] || []) - done).empty?

      payload =
        if all
          ready_payload(event, marker, store)
        else
          event.payload.merge("analytics" => marker.merge("metrics_done" => done, "store" => store))
        end
      event.update!(payload:)
      all
    end
  end

  # Accumulate the metric's primitives (string-keyed for jsonb round-trip) so the
  # finalizing job can rebuild the whole filled table with no further fetches.
  def stash(marker, _key, cell)
    store = marker["store"] || { "metrics" => {}, "series" => {} }
    return store if cell == Pito::Analytics::MetricFill::UNAVAILABLE

    cell.result.metrics.each { |k, v| store["metrics"][k.to_s] = { "current" => v[:current], "previous" => v[:previous] } }
    cell.series.each         { |k, v| store["series"][k.to_s] = v }
    store
  end

  # Build the filled ready payload from the stashed primitives (no YouTube calls).
  def ready_payload(event, marker, store)
    scope   = resolve_scope(marker["scope_type"], marker["scope_id"])
    metrics = (store["metrics"] || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = { current: v["current"], previous: v["previous"] } }
    result  = Pito::Analytics::Scalars::Result.new(metrics:, label: window_label(marker["period"]), comparable: false)
    series  = (store["series"] || {}).transform_keys(&:to_sym)

    payload = Pito::MessageBuilder::Analytics::Enhanced.ready_payload(
      scope:, period: marker["period"], result:, intro: marker["intro"], series:, token: marker["token"]
    )
    if event.payload["reply_handle"].present?
      payload["reply_handle"] = event.payload["reply_handle"]
      payload["reply_target"] = event.payload["reply_target"]
    end
    payload
  end

  def window_label(period)
    Pito::Analytics::Window.for(period, reference_date: Date.current).label
  rescue StandardError
    period.to_s
  end

  def empty_result
    Pito::Analytics::Scalars::Result.new(metrics: {}, label: "", comparable: false)
  end

  def resolve_scope(type, id)
    return nil unless %w[Video Game Channel].include?(type.to_s)

    type.constantize.find_by(id:)
  end
end
