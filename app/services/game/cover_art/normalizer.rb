# frozen_string_literal: true

# Fetches the largest IGDB cover image for a Game and attaches the RAW bytes
# UNCHANGED as `game.cover_art` (the master blob). Display resizing is handled
# by ActiveStorage named variants at render time (:detail / :strip).
#
# Source: t_1080p — the largest IGDB CDN size, serving portrait game covers at
# up to ~810×1080px. The raw bytes are attached as-is: no libvips processing,
# no colour-space coercion, no JPEG re-encode.
#
# Idempotency (two gates):
#   1. mtime gate — if the attachment was created AFTER `game.igdb_synced_at`
#      the cover is considered fresh and the CDN is not queried at all (short-
#      circuits the whole call). Re-syncing via Game::Igdb::SyncGame bumps
#      `igdb_synced_at` first, so this gate is transparent to the sync path.
#   2. digest gate — after fetching, if the raw bytes' MD5 matches the stored
#      blob checksum the attachment is left untouched (no new blob created).
#      This means re-syncs that see the same cover on the CDN are a storage
#      no-op while still paying one CDN round-trip.
#
# Returns the ActiveStorage::Attached::One proxy when attached (or already
# fresh). Returns nil when the Game has no `cover_image_id`.
require "net/http"
require "uri"
require "stringio"
require "digest"

class Game
  module CoverArt
    class Normalizer
      SOURCE_SIZE = "t_1080p"

      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      def initialize(game:, force: false)
        @game  = game
        @force = force
      end

      def call
        return nil if @game.cover_image_id.blank?
        return @game.cover_art if !@force && fresh?

        raw_bytes, content_type = fetch_source_bytes
        return @game.cover_art if !@force && attached_matches?(raw_bytes)

        attach_master(raw_bytes, content_type)
        @game.cover_art
      end

      private

      # True when an attachment already exists and was created AFTER the last
      # IGDB sync (meaning this normalizer already ran for the current sync).
      def fresh?
        return false unless @game.cover_art.attached?
        return false if @game.igdb_synced_at.blank?

        @game.cover_art.attachment.created_at >= @game.igdb_synced_at
      end

      # True when the current blob's MD5 checksum matches the supplied raw bytes.
      # ActiveStorage stores the base64-encoded MD5 digest per blob.
      def attached_matches?(bytes)
        @game.cover_art.attached? &&
          @game.cover_art.blob.checksum == Digest::MD5.base64digest(bytes)
      end

      def fetch_source_bytes
        url      = "https://images.igdb.com/igdb/image/upload/#{SOURCE_SIZE}/#{@game.cover_image_id}.jpg"
        uri      = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.open_timeout  = OPEN_TIMEOUT_SEC
          http.read_timeout  = READ_TIMEOUT_SEC
          http.write_timeout = WRITE_TIMEOUT_SEC
          http.get(uri.request_uri)
        end
        unless response.is_a?(Net::HTTPSuccess)
          raise Pito::Error::ExternalFetchFailed.new(
            source:    "IGDB CDN",
            http_code: response.code,
            detail:    "#{@game.cover_image_id} (#{SOURCE_SIZE})"
          )
        end
        content_type = response["content-type"]&.split(";")&.first&.strip || "image/jpeg"
        [ response.body, content_type ]
      end

      def attach_master(raw_bytes, content_type)
        @game.cover_art.attach(
          io:           StringIO.new(raw_bytes),
          filename:     "cover-#{@game.id}.jpg",
          content_type: content_type
        )
      end
    end
  end
end
