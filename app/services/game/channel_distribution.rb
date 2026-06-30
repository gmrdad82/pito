# frozen_string_literal: true

# Game → channel COVERAGE DISTRIBUTION (item 16). "Across my channels, how is my
# coverage of THIS game distributed?" — a normalized 0–100 share per channel,
# rendered as the offset bar-group in the show-game channel-matches message
# (col 1), beside the channel RECOMMENDATION (col 2).
#
# Same channel set + order as the recommendation column (the caller passes the
# top-N-by-score channels), so the two columns align row-for-row on desktop.
#
# WEIGHT (owner: "combined weighted"): each channel's weight blends three
# NORMALIZED per-metric distributions — videos (count of the game's linked vids on
# that channel), views (Σ Pito::Stats views of those vids), and watch-hours. Only
# metrics that actually have data contribute (their weights re-normalized), so a
# channel with no linked videos gets a 0 share.
#
#   weight(ch) = Σ_metric ( w_metric / Σ active w ) · ( metric(ch) / Σ metric )
#   share%(ch) = weight(ch) · 100, non-zero floored to ≥1, re-normalized to 100.
#
# WATCH-HOURS: per-video lifetime watch-hours are NOT in Pito::Stats
# (views/subscribers only) — they come from a dedicated, 1-day-cached YouTube
# Analytics fetch (Game::ChannelWatchTime), which the FILL JOB runs and injects
# here as `watch_hours` ({ video_id => hours }). When absent/empty, the blend
# re-normalizes over the metrics that do have data (videos + views).
#
# NAMESPACE GOTCHA: inside Game::*, bareword `Game` is the model; use ::Channel /
# ::Video for the other models.
class Game
  class ChannelDistribution
    # Owner default blend weights; re-normalized over metrics that have data.
    WEIGHTS = { videos: 0.2, views: 0.4, watch_hours: 0.4 }.freeze

    Share = Struct.new(:channel, :share, :raw, keyword_init: true)

    # @param game        [::Game]
    # @param channels    [Array<::Channel>] the ordered channels to chart (top-N by score).
    # @param watch_hours [Hash{Integer => Numeric}] video.id => lifetime watch-hours
    #   (from Game::ChannelWatchTime, injected by the fill job). Empty → blend uses
    #   videos + views only.
    # @return [Hash] { nodata: Boolean, shares: Array<Share> } — shares in the
    #   SAME order as `channels`; `nodata: true` when no channel covers the game.
    def self.call(game:, channels:, watch_hours: {})
      new(game:, channels:, watch_hours:).call
    end

    def initialize(game:, channels:, watch_hours: {})
      @game        = game
      @channels    = Array(channels)
      @watch_hours = watch_hours || {}
    end

    def call
      return { nodata: true, shares: [] } if @game.nil? || @channels.empty?

      raws = @channels.map { |ch| raw_for(ch) }
      totals = {
        videos:      raws.sum { |r| r[:videos] },
        views:       raws.sum { |r| r[:views] },
        watch_hours: raws.sum { |r| r[:watch_hours] }
      }

      active = WEIGHTS.select { |metric, w| w.positive? && totals[metric].positive? }
      return { nodata: true, shares: [] } if active.empty?

      wsum    = active.values.sum
      weights = raws.map do |r|
        active.sum { |metric, w| (w / wsum) * (r[metric].to_f / totals[metric]) }
      end

      pcts = normalize_to_100(weights)
      shares = @channels.each_with_index.map do |ch, i|
        r = raws[i]
        Share.new(channel: ch, share: pcts[i],
                  raw: { videos: r[:videos], views: r[:views], watch_hours: r[:watch_hours] })
      end
      { nodata: false, shares: shares }
    end

    private

    # The game's linked videos that live on this channel → {videos, views, watch_hours}.
    def raw_for(channel)
      vids = @game.linked_videos.select { |v| v.channel_id == channel.id }
      {
        channel:     channel,
        videos:      vids.size,
        views:       vids.sum { |v| Pito::Stats.get(v, :views).to_i },
        watch_hours: vids.sum { |v| @watch_hours[v.id].to_f }
      }
    end

    # Fractions (summing to ~1) → integer percentages summing to 100, with every
    # non-zero fraction floored to at least 1 (owner: "0.1 shows as 1; adjust the
    # others so all add up to 100"). Drift from rounding is absorbed by the
    # largest share so the total is exactly 100.
    def normalize_to_100(weights)
      pcts = weights.map { |w| w.positive? ? [ (w * 100).round, 1 ].max : 0 }
      diff = 100 - pcts.sum
      return pcts if diff.zero? || pcts.all?(&:zero?)

      idx = pcts.each_index.max_by { |i| pcts[i] }
      pcts[idx] = [ pcts[idx] + diff, 1 ].max
      pcts
    end
  end
end
