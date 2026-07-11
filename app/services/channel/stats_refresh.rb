# frozen_string_literal: true

# Materialize a Channel's `likes` stat as the sum of its videos' like counts.
#
# YouTube exposes no channel-level like counter — subscribers and views come
# straight from the channels API (ChannelSync), but likes only exist per
# video. This sums the `likes` stat across the channel's videos and upserts
# the result via `Pito::Stats.set` (the channels list reads
# `Pito::Stats.get(channel, :likes)`, never live-sums at render).
#
# Channels with no videos (or no like stats yet) materialize 0 — "computed,
# none" rather than "never computed" (no row).
#
# Invoked from `ChannelStatsRefreshJob`; enqueued after every pass that
# rewrites video like counts (nightly video sync, intraday snapshots).
class Channel
  class StatsRefresh
    def self.call(channel)
      new(channel).call
    end

    def initialize(channel)
      @channel = channel
    end

    def call
      Pito::Stats.set(@channel, :likes, total_video_likes)
    end

    private

    def total_video_likes
      Stat
        .where(entity_type: "Video", kind: "likes")
        .where(entity_id: @channel.videos.select(:id))
        .sum(:value)
    end
  end
end
