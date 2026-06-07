# frozen_string_literal: true

require "net/http"
require "uri"

module Pito
  module Image
    # Fetches a remote image URL and normalizes it to a WxH center-cropped JPEG,
    # returning the JPEG bytes (binary String).
    #
    # Used to build LOCAL ActiveStorage copies of YouTube CDN images (channel
    # avatars, video thumbnails) so the app never hotlinks yt3.ggpht.com /
    # i.ytimg.com — which rate-limit (HTTP 429) when embedded directly in pages.
    #
    # Mirrors Game::CoverArt::Normalizer's fetch + libvips center-crop approach,
    # but takes an arbitrary source URL (the YouTube API hands us the URL) and
    # follows a couple of redirects (the CDN occasionally 302s).
    #
    # Raises Pito::Error::ExternalFetchFailed on a non-2xx terminal response.
    class Normalizer
      JPEG_QUALITY      = 90
      MAX_REDIRECTS     = 3
      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      def initialize(url:, width:, height:)
        @url    = url
        @width  = width
        @height = height
      end

      # @return [String] normalized JPEG bytes.
      def call
        normalize(fetch_bytes(@url, MAX_REDIRECTS))
      end

      private

      def fetch_bytes(url, redirects_left)
        uri      = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout  = OPEN_TIMEOUT_SEC
          http.read_timeout  = READ_TIMEOUT_SEC
          http.write_timeout = WRITE_TIMEOUT_SEC
          http.get(uri.request_uri)
        end

        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPRedirection
          raise_fetch_failed(response) if redirects_left.zero? || response["location"].blank?
          fetch_bytes(response["location"], redirects_left - 1)
        else
          raise_fetch_failed(response)
        end
      end

      def raise_fetch_failed(response)
        raise Pito::Error::ExternalFetchFailed.new(
          source:    "YouTube CDN",
          http_code: response.code,
          detail:    @url.to_s
        )
      end

      # Center-crop to the target aspect, then resize to exactly WxH, JPEG out.
      def normalize(buffer)
        require "vips"
        img = Vips::Image.new_from_buffer(buffer, "")

        target_aspect = @width.to_f / @height
        source_aspect = img.width.to_f / img.height

        if (source_aspect - target_aspect).abs > 0.001
          if source_aspect > target_aspect
            new_w    = (img.height * target_aspect).round
            x_offset = ((img.width - new_w) / 2).round
            img      = img.crop(x_offset, 0, new_w, img.height)
          else
            new_h    = (img.width / target_aspect).round
            y_offset = ((img.height - new_h) / 2).round
            img      = img.crop(0, y_offset, img.width, new_h)
          end
        end

        img = img.resize(@width.to_f / img.width)
        img.jpegsave_buffer(Q: JPEG_QUALITY, strip: true, optimize_coding: true)
      end
    end
  end
end
