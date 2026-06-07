# frozen_string_literal: true

require "stringio"

class Video
  module Thumbnail
    # Downloads a video's YouTube thumbnail from the given source URL, normalizes
    # it to a canonical 480x270 (16:9) JPEG via Pito::Image::Normalizer, and
    # attaches it to `video.thumbnail` (ActiveStorage). Serves OUR copy instead
    # of hotlinking i.ytimg.com (which 429s).
    #
    # Best-effort: a fetch/normalize failure is logged and swallowed so a CDN
    # hiccup never breaks a video sync/import.
    #
    # Returns the attachment proxy when attached, else nil.
    class Ingest
      WIDTH  = 480
      HEIGHT = 270

      def initialize(video:, source_url:)
        @video      = video
        @source_url = source_url.to_s
      end

      def call
        return nil if @source_url.blank?

        bytes = Pito::Image::Normalizer.new(url: @source_url, width: WIDTH, height: HEIGHT).call
        @video.thumbnail.attach(
          io:           StringIO.new(bytes),
          filename:     "thumbnail.jpg",
          content_type: "image/jpeg"
        )
        @video.thumbnail
      rescue Pito::Error::ExternalFetchFailed, Vips::Error => e
        Rails.logger.warn("[Video::Thumbnail::Ingest] failed for video id=#{@video.id}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
