# frozen_string_literal: true

require "net/http"
require "uri"
require "stringio"
require "digest"

class Video
  module Thumbnail
    # Downloads a video's YouTube thumbnail from the given source URL (prefer
    # maxresdefault) and attaches the RAW unprocessed bytes as `video.thumbnail`
    # (the master blob). Display resizing is handled by the ActiveStorage named
    # variant `:display` declared on the model — no resize before attach.
    #
    # Digest-gate: re-attaches ONLY when the raw source bytes' checksum changes,
    # so a sync returning the same thumbnail leaves the blob — and its derived
    # variants — untouched.
    #
    # Best-effort: a fetch failure is logged and swallowed so a CDN hiccup never
    # breaks a video sync/import.
    #
    # Returns the attachment proxy when attached, else nil.
    class Ingest
      MAX_REDIRECTS     = 3
      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      def initialize(video:, source_url:)
        @video      = video
        @source_url = source_url.to_s
      end

      def call
        return nil if @source_url.blank?

        raw_bytes, content_type = fetch_raw(@source_url, MAX_REDIRECTS)

        # Digest-gate: re-attach ONLY when the raw source bytes changed.
        return @video.thumbnail if attached_matches?(raw_bytes)

        @video.thumbnail.attach(
          io:           StringIO.new(raw_bytes),
          filename:     "thumbnail-#{@video.id}.jpg",
          content_type: content_type
        )
        @video.thumbnail
      rescue Pito::Error::ExternalFetchFailed => e
        Rails.logger.warn("[Video::Thumbnail::Ingest] failed for video id=#{@video.id}: #{e.class}: #{e.message}")
        nil
      end

      private

      # True when a thumbnail is already attached and its blob checksum matches
      # the raw source bytes (ActiveStorage stores a base64 MD5 checksum per blob).
      def attached_matches?(bytes)
        @video.thumbnail.attached? &&
          @video.thumbnail.blob.checksum == Digest::MD5.base64digest(bytes)
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
