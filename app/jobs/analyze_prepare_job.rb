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
        result = (cache[signature(marker)] ||= compute(marker))
        write_ready(event, broadcaster, result:)
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

  # Scope signature so the two messages (same level/ids/period) share one fan-out.
  def signature(marker)
    [ marker["level"], Array(marker["entity_ids"]).sort, marker["period"] ].join(":")
  end

  def compute(marker)
    window = Pito::Analytics::Window.for(marker["period"], reference_date: Date.current)
    groups = groups_for(marker["level"], Array(marker["entity_ids"]))
    return Pito::Analytics::Scalars::UNAVAILABLE if groups.empty?

    current  = Pito::Analytics::Primitives.fetch(groups:, window:)
    previous = window.previous && Pito::Analytics::Primitives.fetch(groups:, window: window.previous)
    metrics  = Pito::Analytics::Aggregate.scalars(current:, previous:)
    Pito::Analytics::Scalars::Result.new(metrics:, label: window.label, comparable: window.comparable?)
  rescue StandardError => e
    Rails.logger.warn("[AnalyzePrepareJob] #{marker['level']} #{marker['entity_ids'].inspect}: #{e.class}: #{e.message}")
    Pito::Analytics::Scalars::UNAVAILABLE
  end

  def write_ready(event, broadcaster, result:)
    event.update!(payload: Pito::MessageBuilder::Analyze::Message.ready_payload(event, result:))
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
