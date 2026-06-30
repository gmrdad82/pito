# frozen_string_literal: true

require "net/http"
require "uri"
require "stringio"
require "digest"

class Channel
  module Banner
    # Downloads the YouTube banner from the given source URL
    # (brandingSettings.image.banner_external_url), fetches the ORIGINAL
    # 2560×1440 master via the =w2560-h1440 suffix, and attaches the RAW bytes
    # unchanged as `channel.banner` (the master blob). Display resizing is
    # handled by ActiveStorage named variants at render time (:display).
    #
    # Digest-gate: re-attaches ONLY when the raw source bytes' checksum changes,
    # so a sync returning the same banner leaves the blob — and its derived
    # variants — untouched.
    #
    # Best-effort: a fetch failure is logged and swallowed (the detail card falls
    # back gracefully) so a CDN hiccup never breaks a sync.
    #
    # Returns the attachment proxy when attached, else nil.
    class Ingest
      # The raw bannerExternalUrl serves only a small 512x288 default; appending
      # this size suffix requests the ORIGINAL 2560×1440 (16:9) master.
      SIZE_SUFFIX = "=w2560-h1440"

      MAX_REDIRECTS     = 3
      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      def initialize(channel:, source_url:)
        @channel    = channel
        @source_url = source_url.to_s
      end

      def call
        return nil if @source_url.blank?

        raw_bytes, content_type = fetch_raw(full_res_url, MAX_REDIRECTS)

        # Digest-gate: re-attach ONLY when the raw source bytes changed.
        return @channel.banner if attached_matches?(raw_bytes)

        @channel.banner.attach(
          # Channel-unique filename — same CDN-cache hardening rationale as the
          # avatar (see Channel::Avatar::Ingest).
          io:           StringIO.new(raw_bytes),
          filename:     "banner-#{@channel.id}.jpg",
          content_type: content_type
        )
        @channel.banner
      rescue Pito::Error::ExternalFetchFailed => e
        Rails.logger.warn("[Channel::Banner::Ingest] failed for channel id=#{@channel.id}: #{e.class}: #{e.message}")
        nil
      end

      private

      # True when a banner is already attached and its blob checksum matches the
      # raw source bytes (ActiveStorage stores a base64 MD5 checksum per blob).
      def attached_matches?(bytes)
        @channel.banner.attached? &&
          @channel.banner.blob.checksum == Digest::MD5.base64digest(bytes)
      end

      # Request the original-resolution banner. bannerExternalUrl is suffix-less;
      # if a suffix is somehow already present, replace it rather than double it.
      def full_res_url
        @source_url.sub(/=[^=\/]*\z/, "") + SIZE_SUFFIX
      end

      # Fetches raw bytes from +url+, following up to +redirects_left+
      # redirects. Returns [body_string, content_type_string].
      # Raises Pito::Error::ExternalFetchFailed on a non-2xx terminal response.
      def fetch_raw(url, redirects_left)
        uri      = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout  = OPEN_TIMEOUT_SEC
          http.read_timeout  = READ_TIMEOUT_SEC
          http.write_timeout = WRITE_TIMEOUT_SEC
          http.get(uri.request_uri)
        end

        case response
        when Net::HTTPSuccess
          content_type = response["content-type"]&.split(";")&.first&.strip || "image/jpeg"
          [ response.body, content_type ]
        when Net::HTTPRedirection
          raise_fetch_failed(url, response) if redirects_left.zero? || response["location"].blank?
          fetch_raw(response["location"], redirects_left - 1)
        else
          raise_fetch_failed(url, response)
        end
      end

      def raise_fetch_failed(url, response)
        raise Pito::Error::ExternalFetchFailed.new(
          source:    "YouTube CDN",
          http_code: response.code,
          detail:    url.to_s
        )
      end
    end
  end
end
