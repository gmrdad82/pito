# frozen_string_literal: true

# Dedicated LIFETIME watch-time fold for the channel-distribution blend.
# Deliberately NOT the Pito::Analytics pipeline (which is period-scoped + has its
# own primitives cache). The actual fetch/cache now lives in the shared
# ::Channel::Youtube::LifetimeVideoReport (one cache entry per channel, shared
# with AchievementsRefreshJob's P20 batching) — this class keeps only the
# per-channel folding into { youtube_video_id => minutes } and the graceful
# blend-fallback posture (a bad fetch degrades the distribution column, it
# never raises through it).
#
# NAMESPACE GOTCHA: inside Game::*, bareword `Game` is the model; use ::Channel /
# ::Video / ::Channel::Youtube::LifetimeVideoReport for the others.
class Game
  class ChannelWatchTime
    CACHE_TTL = 1.day # this consumer's max_age for the shared lifetime report

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
        minutes = channel_minutes(channel) # { youtube_video_id => minutes }
        vids.each do |v|
          m = minutes[v.youtube_video_id]
          result[v.id] = (m.to_i / 60.0).round(1) if m && m.to_i.positive?
        end
      end
      result
    end

    private

    # Lifetime per-video watched-minutes for one channel — { youtube_video_id =>
    # minutes }. {} when the channel has no usable connection (the shared report
    # already guards that) or the fetch fails (graceful — the blend falls back
    # to videos + views).
    def channel_minutes(channel)
      rows = ::Channel::Youtube::LifetimeVideoReport.rows_for(channel: channel, max_age: CACHE_TTL)
      Array(rows).to_h { |r| [ r[:video_id], r[:estimated_minutes_watched].to_i ] }
    rescue StandardError => e
      Rails.logger.warn("[ChannelWatchTime] channel #{channel&.id}: #{e.class}: #{e.message}")
      {}
    end
  end
end
