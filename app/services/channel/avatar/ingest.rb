# frozen_string_literal: true

require "net/http"
require "uri"
require "stringio"
require "digest"

class Channel
  module Avatar
    # Downloads the YouTube avatar from the given source URL, fetches the RAW
    # source bytes, and attaches them unchanged as `channel.avatar` (the master
    # blob). Display resizing is handled by ActiveStorage named variants at
    # render time (:lg → 120×120, :sm → 60×60).
    #
    # Digest-gate: re-attaches ONLY when the raw source bytes' checksum changes,
    # so a sync that returns the same avatar leaves the blob — and its derived
    # variants — untouched, avoiding needless churn.
    #
    # Best-effort: a fetch failure is logged and swallowed (the channel list
    # falls back to its placeholder) so a CDN hiccup never breaks a sync.
    #
    # Returns the attachment proxy when attached, else nil.
    class Ingest
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

        raw_bytes, content_type = fetch_raw(@source_url, MAX_REDIRECTS)

        # Digest-gate: re-attach ONLY when the raw source bytes changed.
        return @channel.avatar if attached_matches?(raw_bytes)

        @channel.avatar.attach(
          io:           StringIO.new(raw_bytes),
          # Channel-unique filename (NOT a shared "avatar.jpg"): the ActiveStorage
          # representation-proxy URL ends in the blob filename, and every avatar
          # otherwise shares the identical variation segment + "avatar.jpg" tail — so
          # a CDN cache key that collapses on that tail could serve one channel's
          # avatar for another (the wrong-avatar bug seen on Cloudflare). A per-channel
          # filename makes the URL tail distinct too, hardening against that.
          filename:     "avatar-#{@channel.id}.jpg",
          content_type: content_type
        )
        @channel.avatar
      rescue Pito::Error::ExternalFetchFailed => e
        Rails.logger.warn("[Channel::Avatar::Ingest] failed for channel id=#{@channel.id}: #{e.class}: #{e.message}")
        nil
      end

      private

      # True when an avatar is already attached and its blob checksum matches the
      # raw source bytes (ActiveStorage stores a base64 MD5 checksum per blob).
      def attached_matches?(bytes)
        @channel.avatar.attached? &&
          @channel.avatar.blob.checksum == Digest::MD5.base64digest(bytes)
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
