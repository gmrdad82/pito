# frozen_string_literal: true

# Fills the `analyze` :system + :enhanced messages for a turn, then completes it.
#
# The analyze handler emits TWO pending messages (roles system + enhanced) sharing
# ONE scope; the Finalizer's analyze-pending gate enqueues this job and defers each
# message's per-message thinking-indicator resolve + turn completion to here. So
# each message's spinner stays up until ITS data lands, and its "thought for
# xx.xxs" spans the full fan-out + aggregation (started_at was stamped at dispatch).
#
# Per turn: for each pending analyze event, rebuild the scope (level + entity_ids +
# period from the marker) → fetch per-video / per-channel PRIMITIVES (warm-or-cold)
# for the current and prior windows → aggregate → write the ready payload
# (PERSISTED, so a mid/post-job refresh is correct) → replace_event → resolve THAT
# message's indicator. The aggregate is memoised by scope signature so the two
# messages share one fan-out. The turn completes in `ensure`, only once EVERY
# indicator is resolved. Idempotent on retry (already-ready events are skipped).
class AnalyzePrepareJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)
    cache = {}
    begin
      pending_events(turn).each do |event|
        marker = event.payload["analyze"]
        data   = (cache[signature(marker)] ||= compute(marker))
        write_ready(event, broadcaster, data:)
        broadcaster.resolve_thinking_for(turn:, message_id: event.id)
      end
    ensure
      broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
    end
  end

  private

  def pending_events(turn)
    turn.events.select { |e| Pito::MessageBuilder::Analyze::Message.pending?(e) }
  end

  # Signature per (level, ids, period, ROLE) — roles need different report sets, so
  # each role computes its own scaffold (memoised so a re-run of the same is free).
  def signature(marker)
    [ marker["level"], Array(marker["entity_ids"]).sort, marker["period"], marker["role"] ].join(":")
  end

  # Returns { scaffold: {metric=>bool}, views: chart-data | nil } for the marker's
  # role. `scaffold` is the 0/1 map every metric still uses; `views` is the daily
  # Views chart data (system role only) the bespoke ViewsComponent renders.
  def compute(marker)
    window = Pito::Analytics::Window.for(marker["period"], reference_date: Date.current)
    level  = marker["level"]
    ids    = Array(marker["entity_ids"])
    groups = groups_for(level, ids)
    scaffold = Pito::Analytics::Scaffold.for(groups:, window:, role: marker["role"].to_sym, level: level.to_sym)
    views    = (marker["role"] == "system" ? compute_views(groups:, window:, level:, entity_ids: ids) : nil)
    { scaffold:, views: }
  rescue StandardError => e
    Rails.logger.warn("[AnalyzePrepareJob] #{marker['level']} #{marker['entity_ids'].inspect}: #{e.class}: #{e.message}")
    { scaffold: {}, views: nil } # empty → every cell renders "0", no chart
  end

  # The daily Views series + total + green target for the scope (string-keyed so
  # it round-trips through the jsonb payload). nil when the scope is empty/errors.
  def compute_views(groups:, window:, level:, entity_ids:)
    return nil if groups.empty?

    daily = Pito::Analytics::DailySeries.for(groups:, window:)
    subs  = Pito::Analytics::Thresholds.subs_for(level:, entity_ids:)
    # Prior comparable window total → drives the caption trend triangle. nil for
    # non-comparable windows (e.g. lifetime) → no triangle. Window#previous is the
    # designed trend baseline; its primitives cache under a distinct `-prev` key.
    prev_window = window.previous
    previous    = prev_window && Pito::Analytics::DailySeries.for(groups:, window: prev_window).total
    {
      "series"       => daily.series,
      "total"        => daily.total,
      "previous"     => previous,
      "target_daily" => Pito::Analytics::Thresholds.views_target_daily(subs:)
    }
  rescue StandardError => e
    Rails.logger.warn("[AnalyzePrepareJob#compute_views] #{e.class}: #{e.message}")
    nil
  end

  def write_ready(event, broadcaster, data:)
    event.update!(payload: Pito::MessageBuilder::Analyze::Message.ready_payload(event, data:))
    broadcaster.replace_event(event)
  end

  # level + entity_ids → [[channel, subjects], …] for Primitives.fetch:
  #   channel  → [channel, :channel]              (one channel-wide primitive)
  #   vid/game → [channel, [youtube_video_id, …]] (per-video primitives; games
  #              reuse shared vids across the requested ids)
  def groups_for(level, ids)
    case level
    when "channel"
      ::Channel.where(id: ids).select { |c| usable?(c) }.map { |c| [ c, :channel ] }
    when "vid"
      ::Video.where(id: ids).includes(:channel).group_by(&:channel).filter_map { |ch, vids| usable_group(ch, vids) }
    when "game"
      ::Video.joins(:video_game_links).where(video_game_links: { game_id: ids })
             .includes(:channel).distinct.group_by(&:channel).filter_map { |ch, vids| usable_group(ch, vids) }
    else
      []
    end
  end

  def usable_group(channel, videos)
    return nil unless usable?(channel)

    ids = videos.filter_map(&:youtube_video_id)
    ids.empty? ? nil : [ channel, ids ]
  end

  def usable?(channel)
    conn = channel&.youtube_connection
    conn.present? && !conn.needs_reauth
  end
end
