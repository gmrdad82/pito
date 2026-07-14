# frozen_string_literal: true

# Read-through for per-video statistics (views / likes / comments).
#
# The recurring fleet already persists these counters into Pito::Stats
# several times a day (nightly + midday reconciles at 01:00/13:00, stats
# snapshots at 09:00/17:00). AchievementsRefreshJob trails each pass by an
# hour, so re-fetching the same numbers from YouTube was pure waste — this
# service answers from the fresh rows and falls back to the API only for
# videos whose rows are missing or stale (self-healing when a producer pass
# failed).
#
# Freshness marker: the `likes` row's synced_at — the producers write
# views+likes+comments together, so one kind's timestamp vouches for all
# three.
#
# Error posture (stale is acceptable, bad data never): an API error RAISES —
# nothing is persisted for a failed slice, no zeros are invented, and the
# caller keeps its own per-channel rescue.
class Channel
  module Youtube
    class VideoStatsReadThrough
      # YouTube videos.list hard cap (1 quota unit per call).
      BATCH_SIZE = 50

      # @param channel [Channel] a channel with a non-nil youtube_connection
      # @param max_age [ActiveSupport::Duration] freshness window for rows
      # @return [Hash{String => Hash}] youtube_video_id =>
      #   { views:, likes:, comments: } (Integers)
      def self.call(channel:, max_age:)
        new(channel: channel, max_age: max_age).call
      end

      def initialize(channel:, max_age:)
        @channel = channel
        @max_age = max_age
      end

      def call
        videos = @channel.videos.where.not(youtube_video_id: nil)
                         .pluck(:id, :youtube_video_id)
        return {} if videos.empty?

        rows      = stats_rows(videos.map(&:first))
        cutoff    = @max_age.ago
        result    = {}
        stale_ids = []

        videos.each do |video_id, yt_id|
          kinds     = rows[video_id] || {}
          likes_row = kinds["likes"]

          if likes_row&.synced_at && likes_row.synced_at >= cutoff
            result[yt_id] = {
              views:    kinds["views"]&.value.to_i,
              likes:    likes_row.value.to_i,
              comments: kinds["comments"]&.value.to_i
            }
          else
            stale_ids << yt_id
          end
        end

        fetch_and_persist(stale_ids, result)
        result
      end

      private

      # Every stat row for the channel's videos in ONE query, grouped
      # video_id => kind => Stat.
      def stats_rows(video_ids)
        ::Stat
          .where(entity_type: ::Video.polymorphic_name, entity_id: video_ids)
          .group_by(&:entity_id)
          .transform_values { |stats| stats.index_by(&:kind) }
      end

      # Fetch stale/missing ids in ≤50 slices, persist (same write shape as
      # VideoStatsSnapshotJob#write_stats) and fold into the result. Raises
      # on API error — deliberately no rescue here.
      def fetch_and_persist(yt_ids, result)
        return if yt_ids.empty?

        client = Channel::Youtube::Client.new(@channel.youtube_connection)
        yt_ids.each_slice(BATCH_SIZE) do |slice|
          response = client.videos_list(ids: slice, parts: %i[statistics])
          Array(response[:items]).each do |item|
            stats = item[:statistics] || {}
            entry = {
              views:    stats[:view_count]&.to_i    || 0,
              likes:    stats[:like_count]&.to_i    || 0,
              comments: stats[:comment_count]&.to_i || 0
            }
            result[item[:id].to_s] = entry
            persist(item[:id].to_s, entry)
          end
        end
      end

      def persist(yt_id, entry)
        video = @channel.videos.find_by(youtube_video_id: yt_id)
        return unless video

        ::Pito::Stats.set(video, :views,    entry[:views])
        ::Pito::Stats.set(video, :likes,    entry[:likes])
        ::Pito::Stats.set(video, :comments, entry[:comments])
      end
    end
  end
end
