# frozen_string_literal: true

# Fetches the largest IGDB cover variant for a Game, normalizes it to a
# canonical 600×800 (3:4) JPEG via libvips, and attaches it to
# `game.cover_art` via ActiveStorage.
#
# Idempotency: skips re-fetch when the attachment already exists and was
# created after `game.igdb_synced_at` (re-sync bumps that timestamp, forcing
# a re-normalize on the next call).
#
# Returns the ActiveStorage::Attached::One proxy when attached (or already
# fresh). Returns nil when the Game has no `cover_image_id`.
require "net/http"
require "uri"
require "tempfile"

class Game
  module CoverArt
    class Normalizer
      MASTER_W       = 600
      MASTER_H       = 800
      JPEG_QUALITY   = 95
      SOURCE_SIZE    = "t_cover_big_2x"

      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      def initialize(game:)
        @game = game
      end

      def call
        return nil if @game.cover_image_id.blank?
        return @game.cover_art if fresh?

        buffer = fetch_source_bytes
        img    = normalize(buffer)
        attach_to_game(img)

        @game.cover_art
      end

      private

      def fresh?
        return false unless @game.cover_art.attached?
        return false if @game.igdb_synced_at.blank?

        @game.cover_art.attachment.created_at >= @game.igdb_synced_at
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
        response.body
      end

      def attach_to_game(img)
        Tempfile.create([ "cover_art_#{@game.id}", ".jpg" ]) do |tmp|
          tmp.binmode
          img.jpegsave(tmp.path, Q: JPEG_QUALITY, strip: true, optimize_coding: true)
          tmp.rewind
          @game.cover_art.attach(
            io:           tmp,
            filename:     "cover.jpg",
            content_type: "image/jpeg"
          )
        end
      end

      def normalize(buffer)
        require "vips"
        img = Vips::Image.new_from_buffer(buffer, "")

        target_aspect = MASTER_W.to_f / MASTER_H
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

        img.resize(MASTER_W.to_f / img.width)
      end
    end
  end
end
