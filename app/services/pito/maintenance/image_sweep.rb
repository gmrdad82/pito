# frozen_string_literal: true

module Pito
  module Maintenance
    # Sweeps ActiveStorage image attachments — game covers (`Game#cover_art`) and
    # video thumbnails (`Video#thumbnail`) — for blobs whose underlying FILE is
    # missing from the storage service. The attachment + blob row still exist, but
    # `service.exist?(blob.key)` is false (e.g. a wiped `storage/` dir), so the
    # rendered `<img>` 404s. This is exactly the "broken Pragmata cover" symptom.
    #
    #   ImageSweep.missing  → { games: [Game], videos: [Video] } with a missing file
    #   ImageSweep.repair   → re-attach from source; returns a counts Hash
    #
    # Repair sources:
    #   * games  — re-fetch from IGDB via `Game::CoverArt::Normalizer(force: true)`
    #              (the `cover_image_id` is stored, so this is self-contained).
    #   * videos — the remote thumbnail URL is NOT persisted, so we re-read it from
    #              YouTube (owner connection) and re-ingest. Videos on a missing /
    #              reauth-needed connection are skipped (reported, not fixed).
    module ImageSweep
      module_function

      # @return [Hash{Symbol=>Array}] games + videos whose blob file is missing.
      def missing
        {
          games:  ::Game.with_attached_cover_art.select  { |g| blob_missing?(g.cover_art) },
          videos: ::Video.with_attached_thumbnail.select { |v| blob_missing?(v.thumbnail) }
        }
      end

      # Re-attach every image with a missing file.
      # @return [Hash] { games_fixed:, videos_fixed:, videos_skipped: }
      def repair
        m = missing
        games_fixed = m[:games].count { |g| repair_game(g) }
        fixed, skipped = m[:videos].partition { |v| repair_video(v) }
        { games_fixed: games_fixed, videos_fixed: fixed.size, videos_skipped: skipped.size }
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
