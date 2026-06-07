# frozen_string_literal: true

require "stringio"

class Channel
  module Avatar
    # Downloads a channel's YouTube avatar from the given source URL, normalizes
    # it to a canonical 240x240 square JPEG via Pito::Image::Normalizer, and
    # attaches it to `channel.avatar` (ActiveStorage). This is how we serve our
    # OWN copy of the avatar instead of hotlinking yt3.ggpht.com (which 429s).
    #
    # Best-effort: a fetch/normalize failure is logged and swallowed (the channel
    # list falls back to its placeholder) so a CDN hiccup never breaks a sync.
    #
    # Returns the attachment proxy when attached, else nil.
    class Ingest
      SIZE = 240

      def initialize(channel:, source_url:)
        @channel    = channel
        @source_url = source_url.to_s
      end

      def call
        return nil if @source_url.blank?

        bytes = Pito::Image::Normalizer.new(url: @source_url, width: SIZE, height: SIZE).call
        @channel.avatar.attach(
          io:           StringIO.new(bytes),
          filename:     "avatar.jpg",
          content_type: "image/jpeg"
        )
        @channel.avatar
      rescue Pito::Error::ExternalFetchFailed, Vips::Error => e
        Rails.logger.warn("[Channel::Avatar::Ingest] failed for channel id=#{@channel.id}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
