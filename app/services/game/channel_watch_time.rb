# frozen_string_literal: true

# Dedicated LIFETIME watch-time fetch for the channel-distribution blend.
# Deliberately NOT the Pito::Analytics pipeline (which is period-scoped + has its
# own primitives cache): this is one lightweight per-channel YouTube Analytics
# call for all-time `estimatedMinutesWatched` per video, cached for 1 DAY. It is
# heavy (an API round-trip per covering channel) — which is exactly why the
# distribution column streams in progressively (run from ChannelDistributionFillJob).
#
# NAMESPACE GOTCHA: inside Game::*, bareword `Game` is the model; use ::Channel /
# ::Video / ::Channel::Youtube::AnalyticsClient for the others.
class Game
  class ChannelWatchTime
    CACHE_TTL      = 1.day
    # YouTube launch — a safe all-time floor so the window covers a video's whole life.
    LIFETIME_START = Date.new(2005, 2, 14)

    # @param videos [Array<::Video>] the videos to get lifetime watch-hours for.
    # @return [Hash{Integer => Float}] video.id => lifetime watch-hours (only for
    #   videos with data; absent/zero ones are simply not present).
    def self.hours_for(videos:)
      new(videos: videos).hours_for
    end

    def initialize(videos:)
      @videos = Array(videos)
    end

    def hours_for
      result = {}
      @videos.group_by(&:channel).each do |channel, vids|
        minutes = channel_minutes(channel) # { youtube_video_id => minutes }, cached 1d
        vids.each do |v|
          m = minutes[v.youtube_video_id]
          result[v.id] = (m.to_i / 60.0).round(1) if m && m.to_i.positive?
        end
      end
      result
    end

    private

    # Lifetime per-video watched-minutes for one channel — { youtube_video_id =>
    # minutes }. Cached for 1 day; {} when the channel has no usable connection or
    # the API call fails (graceful — the blend falls back to videos + views).
    def channel_minutes(channel)
      conn = channel&.youtube_connection
      return {} unless conn && channel.youtube_channel_id.present?

      Rails.cache.fetch(cache_key(channel), expires_in: CACHE_TTL) do
        rows = ::Channel::Youtube::AnalyticsClient.new(conn).top_videos(
          channel_id: channel.youtube_channel_id,
          start_date: LIFETIME_START,
          end_date:   Date.current
        )
        Array(rows).to_h { |r| [ r[:video_id], r[:estimated_minutes_watched].to_i ] }
      end
    rescue StandardError => e
      Rails.logger.warn("[ChannelWatchTime] channel #{channel&.id}: #{e.class}: #{e.message}")
      {}
    end

    def cache_key(channel)
      "pito:watch_time:lifetime:channel:#{channel.id}"
    end
  end
end
