# frozen_string_literal: true

# Fills the show-game channel-matches message's DISTRIBUTION column.
# `show game` emits that message INSTANTLY with col 1 as a NoData canvas + a
# `channel_distribution` pending marker; the Finalizer enqueues this job and
# defers resolving the message's thinking indicator + completing the turn.
#
# For each pending channel-matches event: compute the per-channel coverage shares
# (Game::ChannelDistribution over the same top-5-by-score channels the message
# shows), rewrite the event to its READY body (col 1 = offset bars, or NoData when
# nothing covers the game), persist it (so a refresh shows the data, not the
# skeleton), broadcast the swap (replace_event), resolve that message's indicator,
# and — once every indicator in the turn is resolved — complete the turn. Mirrors
# AnalyticsFillJob#finalize; coordinates with the analytics fill via
# all_thinking_resolved? (whichever job finishes last completes the turn).
class ChannelDistributionFillJob < ApplicationJob
  queue_as :default

  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    broadcaster = Pito::Stream::Broadcaster.new(conversation: turn.conversation)

    turn.events.where(kind: :enhanced).find_each do |event|
      next unless Pito::MessageBuilder::Game::Channels.pending?(event)

      fill(event)
      broadcaster.replace_event(event)
      broadcaster.resolve_thinking_for(turn:, message_id: event.id)
    end

    broadcaster.complete_turn(turn:) if broadcaster.all_thinking_resolved?(turn:)
  end

  private

  # Compute the shares + rewrite the event payload to its ready (filled) body.
  def fill(event)
    marker = event.payload["channel_distribution"]
    game   = ::Game.find_by(id: marker["game_id"])

    shares =
      if game
        channels = Pito::Recommendations.channels_for(game, include_all: true)
                                        .first(Pito::Games::ChannelsComponent::TOP_N)
                                        .map(&:channel)
        # Dedicated, 1-day-cached lifetime watch-time fetch (heavy → that's why this
        # runs in the async fill job), feeding the videos + views + watch-time blend.
        channel_ids = channels.map(&:id)
        covering    = game.linked_videos.select { |v| channel_ids.include?(v.channel_id) }
        watch_hours = Game::ChannelWatchTime.hours_for(videos: covering)
        result = Game::ChannelDistribution.call(game: game, channels: channels, watch_hours: watch_hours)
        result[:nodata] ? nil : result[:shares]
      end

    body =
      if game
        Pito::MessageBuilder::Game::Channels.ready_body(
          game: game, intro: marker["intro"],
          distribution_caption: marker["distribution_caption"],
          recommendation_caption: marker["recommendation_caption"], shares: shares
        )
      else
        event.payload["body"] # game gone — leave the body as-is, just resolve
      end

    event.update!(
      payload: event.payload.merge(
        "body"                 => body,
        "channel_distribution" => marker.merge("status" => "ready")
      )
    )
  end
end
