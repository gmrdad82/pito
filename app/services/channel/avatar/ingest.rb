# frozen_string_literal: true

require "stringio"
require "digest"

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

        # Digest-gate: re-attach ONLY when the normalized image actually changed
        # (owner 2026-06-29). A sync that returns the same avatar leaves the blob —
        # and its derived variants — untouched, avoiding needless churn.
        return @channel.avatar if attached_matches?(bytes)

        @channel.avatar.attach(
          io:           StringIO.new(bytes),
          # Channel-unique filename (NOT a shared "avatar.jpg"): the ActiveStorage
          # representation-proxy URL ends in the blob filename, and every avatar
          # otherwise shares the identical variation segment + "avatar.jpg" tail — so
          # a CDN cache key that collapses on that tail could serve one channel's
          # avatar for another (the wrong-avatar bug seen on Cloudflare). A per-channel
          # filename makes the URL tail distinct too, hardening against that.
          filename:     "avatar-#{@channel.id}.jpg",
          content_type: "image/jpeg"
        )
        @channel.avatar
      rescue Pito::Error::ExternalFetchFailed, Vips::Error => e
        Rails.logger.warn("[Channel::Avatar::Ingest] failed for channel id=#{@channel.id}: #{e.class}: #{e.message}")
        nil
      end

      private

      # True when an avatar is already attached and its blob checksum matches the
      # new bytes (ActiveStorage stores a base64 MD5 checksum per blob).
      def attached_matches?(bytes)
        @channel.avatar.attached? &&
          @channel.avatar.blob.checksum == Digest::MD5.base64digest(bytes)
      end
    end
  end
end
