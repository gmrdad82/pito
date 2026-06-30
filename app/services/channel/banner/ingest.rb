# frozen_string_literal: true

require "stringio"
require "digest"

class Channel
  module Banner
    # Downloads a channel's YouTube banner from the given source URL
    # (brandingSettings.image.banner_external_url), normalizes it to a canonical
    # 374x210 (16:9) JPEG via Pito::Image::Normalizer — the SAME box as a video
    # thumbnail — and attaches it to `channel.banner` (ActiveStorage). This serves
    # OUR copy of the banner instead of hotlinking the YouTube CDN.
    #
    # Mirrors Channel::Avatar::Ingest. Best-effort: a fetch/normalize failure is
    # logged and swallowed (the detail card falls back to the avatar in the banner
    # spot) so a CDN hiccup never breaks a sync.
    #
    # Returns the attachment proxy when attached, else nil.
    class Ingest
      WIDTH  = 374
      HEIGHT = 210

      # The raw bannerExternalUrl serves only a small 512x288 default; appending
      # this size suffix returns the ORIGINAL 2560x1440 (16:9) banner, which we
      # then downscale to 374x210. Source and target are both 16:9, so the
      # Normalizer's center-crop is a clean resize (no sides lost).
      SIZE_SUFFIX = "=w2560-h1440"

      def initialize(channel:, source_url:)
        @channel    = channel
        @source_url = source_url.to_s
      end

      def call
        return nil if @source_url.blank?

        bytes = Pito::Image::Normalizer.new(url: full_res_url, width: WIDTH, height: HEIGHT).call

        # Digest-gate: re-attach ONLY when the normalized banner actually changed
        # (owner 2026-06-29) — a sync returning the same banner leaves the blob alone.
        return @channel.banner if attached_matches?(bytes)

        @channel.banner.attach(
          # Channel-unique filename (NOT a shared "banner.jpg") — same CDN-cache
          # hardening as the avatar (see Channel::Avatar::Ingest).
          io:           StringIO.new(bytes),
          filename:     "banner-#{@channel.id}.jpg",
          content_type: "image/jpeg"
        )
        @channel.banner
      rescue Pito::Error::ExternalFetchFailed, Vips::Error => e
        Rails.logger.warn("[Channel::Banner::Ingest] failed for channel id=#{@channel.id}: #{e.class}: #{e.message}")
        nil
      end

      private

      # True when a banner is already attached and its blob checksum matches the
      # new bytes (ActiveStorage stores a base64 MD5 checksum per blob).
      def attached_matches?(bytes)
        @channel.banner.attached? &&
          @channel.banner.blob.checksum == Digest::MD5.base64digest(bytes)
      end

      # Request the original-resolution banner. bannerExternalUrl is suffix-less;
      # if a suffix is somehow already present, replace it rather than double it.
      def full_res_url
        @source_url.sub(/=[^=\/]*\z/, "") + SIZE_SUFFIX
      end
    end
  end
end
