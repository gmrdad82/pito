# frozen_string_literal: true

# Shared LIFETIME per-video YouTube Analytics report.
#
# Two consumers used to each run their own lifetime `top_videos` call:
# AchievementsRefreshJob (max_age: 12.hours) and Game::ChannelWatchTime
# (max_age: 24.hours). This service unifies them behind one cache entry per
# channel so the same lifetime report is fetched at most twice a day instead
# of 3×+ — freshness stays a per-caller decision (`max_age:`), storage is
# shared.
#
# LIFETIME_START unifies the two consumers' previously different floors
# (2005-01-01 / 2005-02-14) — both predate YouTube's actual launch
# (2005-04-23), so the union is safe: no real video is excluded and no
# extra rows can appear.
#
# Storage TTL is NOT a re-derived constant here — it comes from the single
# window-expiry policy in Pito::Analytics::Window (the lifetime tier; see
# `Window#expires_at_for` / `docs/architecture.md`). Every window-keyed
# cache in the app is required to call through that policy rather than
# hardcode its own TTL math.
#
# DATA HONESTY (owner constraint K2): an API error RAISES to the caller —
# nothing is ever cached on failure, so a bad fetch leaves whatever was
# previously cached (possibly nothing) untouched instead of papering over
# the gap with an empty result. Callers keep their own rescue.
class Channel
  module Youtube
    class LifetimeVideoReport
      CACHE_KEY_PREFIX = "pito:yt:lifetime_top_videos:v1:channel:"
      # Both consumers' old floors predate YouTube's 2005-04-23 launch —
      # the union is a safe no-op, never a source of extra/missing rows.
      LIFETIME_START = Date.new(2005, 1, 1)

      # @param channel [::Channel]
      # @param max_age [ActiveSupport::Duration] how stale a cached fetch may
      #   be before this call forces a refetch.
      # @return [Array<Hash>] full AnalyticsClient#top_videos row hashes
      #   (video_id, views, estimated_minutes_watched, subscribers_gained,
      #   subscribers_lost, likes).
      def self.rows_for(channel:, max_age:)
        new(channel: channel, max_age: max_age).rows_for
      end

      def initialize(channel:, max_age:)
        @channel = channel
        @max_age = max_age
      end

      def rows_for
        return [] unless connected?

        cached = read_cache
        return cached[:rows] if cached && fresh?(cached[:fetched_at])

        fetch_and_store
      end

      private

      def connected?
        @channel&.youtube_connection && @channel.youtube_channel_id.present?
      end

      def fresh?(fetched_at)
        fetched_at.is_a?(Time) && fetched_at >= @max_age.ago
      end

      # A legacy/absent/malformed cache entry (wrong shape, missing keys,
      # non-Time fetched_at) is treated as a miss rather than raising.
      def read_cache
        entry = Rails.cache.read(cache_key)
        return nil unless entry.is_a?(Hash)

        rows       = entry[:rows]
        fetched_at = entry[:fetched_at]
        return nil unless rows.is_a?(Array) && fetched_at.is_a?(Time)

        { rows: rows, fetched_at: fetched_at }
      end

      # Raises on API failure — deliberately no rescue here (K2).
      def fetch_and_store
        analytics = Channel::Youtube::AnalyticsClient.new(@channel.youtube_connection)
        rows = analytics.top_videos(
          channel_id: @channel.youtube_channel_id,
          start_date: LIFETIME_START,
          end_date:   Date.current
        )

        Rails.cache.write(cache_key, { rows: rows, fetched_at: Time.current }, expires_in: storage_expires_in)
        rows
      end

      # Storage TTL from the ONE window-expiry policy — never re-derived.
      def storage_expires_in
        window     = Pito::Analytics::Window.for("lifetime", reference_date: Date.current)
        expires_at = window.expires_at_for(now: Time.current)
        return nil unless expires_at

        expires_at - Time.current
      end

      def cache_key
        "#{CACHE_KEY_PREFIX}#{@channel.id}"
      end
    end
  end
end
