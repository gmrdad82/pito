# frozen_string_literal: true

module Pito
  module Maintenance
    # Sweeps ActiveStorage image attachments — game covers (`Game#cover_art`),
    # video thumbnails (`Video#thumbnail`), and channel avatars (`Channel#avatar`)
    # — for blobs whose underlying FILE is missing from the storage service.
    # The attachment + blob row still exist, but `service.exist?(blob.key)` is
    # false (e.g. a wiped `storage/` dir or a migration to a new root), so the
    # rendered `<img>` 404s. This is exactly the "broken Pragmata cover" symptom.
    #
    #   ImageSweep.missing  → { games: [Game], videos: [Video], channels: [Channel] }
    #   ImageSweep.repair   → re-attach from source; returns a counts Hash
    #
    # Repair sources:
    #   * games    — re-fetch from IGDB via `Game::CoverArt::Normalizer(force: true)`
    #                (the `cover_image_id` is stored, so this is self-contained).
    #   * videos   — the remote thumbnail URL is NOT persisted, so we re-read it from
    #                YouTube (owner connection) and re-ingest. Videos on a missing /
    #                reauth-needed connection are skipped (reported, not fixed).
    #   * channels — the avatar URL is re-fetched from YouTube via
    #                `Channel::Youtube::Client#fetch_channel` (mine:true — one
    #                channel per connection). Channels on a missing / reauth-needed
    #                connection are skipped (reported, not fixed).
    module ImageSweep
      module_function

      # @return [Hash{Symbol=>Array}] games + videos + channels whose blob file is missing.
      def missing
        {
          games:    ::Game.with_attached_cover_art.select    { |g| blob_missing?(g.cover_art) },
          videos:   ::Video.with_attached_thumbnail.select   { |v| blob_missing?(v.thumbnail) },
          channels: ::Channel.with_attached_avatar.select    { |c| blob_missing?(c.avatar) }
        }
      end

      # Re-attach every image with a missing file.
      # @return [Hash] { games_fixed:, videos_fixed:, videos_skipped:, channels_fixed:, channels_skipped: }
      def repair
        m = missing
        games_fixed = m[:games].count { |g| repair_game(g) }
        fixed_v, skipped_v = m[:videos].partition   { |v| repair_video(v) }
        fixed_c, skipped_c = m[:channels].partition { |c| repair_channel(c) }
        {
          games_fixed:      games_fixed,
          videos_fixed:     fixed_v.size,
          videos_skipped:   skipped_v.size,
          channels_fixed:   fixed_c.size,
          channels_skipped: skipped_c.size
        }
      end

      # True when the attachment exists but its blob's backing file does not.
      def blob_missing?(attached)
        return false unless attached.attached?

        blob = attached.blob
        !blob.service.exist?(blob.key)
      rescue StandardError
        false
      end

      def repair_game(game)
        ::Game::CoverArt::Normalizer.new(game: game, force: true).call
        true
      rescue StandardError => e
        Rails.logger.warn("[ImageSweep] game ##{game.id} cover repair failed: #{e.class}: #{e.message}")
        false
      end

      def repair_video(video)
        connection = video.channel&.youtube_connection
        return false if connection.nil? || connection.needs_reauth?

        fresh = ::Channel::Youtube::VideosReader.new(connection).read_video(video)
        url   = dig_thumbnail_url(fresh)
        return false if url.blank?

        ::Video::Thumbnail::Ingest.new(video: video, source_url: url).call
        true
      rescue StandardError => e
        Rails.logger.warn("[ImageSweep] video ##{video.id} thumbnail repair failed: #{e.class}: #{e.message}")
        false
      end

      # Re-fetch the channel avatar URL from YouTube and re-ingest it.
      # Assumes one channel per connection (`fetch_channel` uses mine:true).
      # Channels with no connection or a reauth-needed connection are skipped.
      def repair_channel(channel)
        connection = channel.youtube_connection
        return false if connection.nil? || connection.needs_reauth?

        client = ::Channel::Youtube::Client.new(connection)
        url    = client.fetch_channel[:avatar_url]
        return false if url.blank?

        ::Channel::Avatar::Ingest.new(channel: channel, source_url: url).call
        true
      rescue StandardError => e
        Rails.logger.warn("[ImageSweep] channel ##{channel.id} avatar repair failed: #{e.class}: #{e.message}")
        false
      end

      # Pull the high-res thumbnail URL from a VideosReader#read_video result,
      # tolerating symbol- or string-keyed hashes.
      def dig_thumbnail_url(fresh)
        snippet = fresh[:snippet] || fresh["snippet"] || {}
        thumbs  = snippet[:thumbnails] || snippet["thumbnails"] || {}
        high    = thumbs[:high] || thumbs["high"] || thumbs[:default] || thumbs["default"] || {}
        high[:url] || high["url"]
      end
    end
  end
end
