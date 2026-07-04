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
#   1. image_id gate — IGDB image ids are immutable content identifiers: a
#      replaced cover gets a NEW `cover_image_id`. The attached blob carries
#      the id it was fetched from in its metadata (`igdb_image_id`); when it
#      matches the game's current `cover_image_id` the master is current and
#      the CDN is not queried at all. (The old gate compared the attachment's
#      created_at against `igdb_synced_at` — which the sync stamps moments
#      earlier, so every nightly re-downloaded all covers, and CDN re-encodes
#      then re-attached unchanged art; the attachment-touch marked ~all
#      awaited games "updated" every night — 1.0.0 G24/G25.)
#   2. digest gate — for blobs attached before the metadata existed: after
#      fetching, if the raw bytes' MD5 matches the stored blob checksum, the
#      id is stamped onto the blob IN PLACE (`blob.update!` — no new blob, no
#      attachment-touch) and future runs take gate 1. Only a real mismatch
#      re-attaches — and a genuinely new cover SHOULD touch the game (cache
#      bust), so `attach` runs normally.
#
# Returns the ActiveStorage::Attached::One proxy when attached (or already
# current). Returns nil when the Game has no `cover_image_id`.
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
        return @game.cover_art if !@force && current_master?

        raw_bytes, content_type = fetch_source_bytes
        if !@force && attached_matches?(raw_bytes)
          stamp_image_id!
          return @game.cover_art
        end

        attach_master(raw_bytes, content_type)
        @game.cover_art
      end

      private

      # Gate 1: the attached master was fetched from the game's CURRENT
      # cover_image_id — nothing to do, no network.
      def current_master?
        @game.cover_art.attached? && stored_image_id == @game.cover_image_id
      end

      # Blob metadata round-trips through JSON, so keys come back as strings;
      # a not-yet-reloaded in-memory blob may still hold the symbol form.
      def stored_image_id
        meta = @game.cover_art.blob.metadata
        meta["igdb_image_id"] || meta[:igdb_image_id]
      end

      # Gate 2: true when the current blob's MD5 checksum matches the supplied
      # raw bytes. ActiveStorage stores the base64-encoded MD5 digest per blob.
      def attached_matches?(bytes)
        @game.cover_art.attached? &&
          @game.cover_art.blob.checksum == Digest::MD5.base64digest(bytes)
      end

      # Backfill the image id onto a pre-metadata blob without re-attaching.
      # A blob update cascades a touch to the game (blob → attachments →
      # `belongs_to :record, touch: true`); the whole point of stamping in
      # place is that an unchanged cover must NOT mark the game updated, so
      # the game leg is suppressed.
      def stamp_image_id!
        blob = @game.cover_art.blob
        Game.no_touching do
          blob.update!(metadata: blob.metadata.merge("igdb_image_id" => @game.cover_image_id))
        end
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
          content_type: content_type,
          metadata:     { "igdb_image_id" => @game.cover_image_id }
        )
      end
    end
  end
end
