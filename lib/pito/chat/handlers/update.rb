# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `update` chat tool — the ONE typed surface for entity
      # metadata writes (the AI suggests these commands; only the owner runs
      # them):
      #
      #   update game footage <id> <hours>      — local write (0.5-step ceil)
      #   update game price <id> <amount>       — local write (euro, 2dp)
      #   update game platform <id> <name>      — local write (adds the family)
      #   update vid description <id> <text>    — confirmation → YouTube push
      #   update vid tags <id> <t1, t2, …>      — confirmation → YouTube push
      #
      # Game fields reuse the same canonical parsers and success copy the
      # retired setter tools used (Pito::Games::{FootageAmount,PriceAmount,
      # PlatformInput}). Vid fields never write directly: they stage a
      # :confirmation event (MessageBuilder::Video::MetadataConfirmation) whose
      # `yes` runs Confirmation::Executor#confirm_video_metadata — local column
      # + a field-restricted VideosClient PUT via VideoRemoteStatusSync.
      class Update < Pito::Chat::Handler
        self.tool = :update
        self.description_key = "pito.chat.update.descriptions.update"

        GAME_FIELDS = %w[footage price platform].freeze
        VID_FIELDS  = %w[description tags].freeze
        NOUNS = {
          "game" => "game", "games" => "game",
          "vid" => "vid", "vids" => "vid", "video" => "vid", "videos" => "vid"
        }.freeze

        # "update <noun> <field> <id> <value…>" — value is rest-of-line RAW.
        PATTERN = /\Aupdate\s+(\S+)\s+(\S+)\s+#?(\d+)\s+(.+)\z/im

        def call
          m = message.raw.to_s.strip.match(PATTERN)
          return usage unless m

          noun  = NOUNS[m[1].downcase]
          field = m[2].downcase
          value = m[4].strip

          case noun
          when "game" then update_game(field, m[3], value)
          when "vid"  then update_vid(field, m[3], value)
          else usage
          end
        end

        private

        # ── game fields (local writes, immediate) ──────────────────────────────

        def update_game(field, id, value)
          return usage unless GAME_FIELDS.include?(field)

          game = ::Game.find_by(id: id)
          return not_found("game ##{id}") unless game

          case field
          when "footage"  then update_footage(game, value)
          when "price"    then update_price(game, value)
          when "platform" then update_platform(game, value)
          end
        end

        def update_footage(game, value)
          hours = Pito::Games::FootageAmount.parse(value.split(/\s+/).first)
          return bad_value("footage", value) if hours.nil?

          game.update!(footage_hours: hours)
          ok_text("pito.copy.footage.updated", game: game.title, hours: format("%gh", hours.to_f))
        end

        def update_price(game, value)
          amount = Pito::Games::PriceAmount.parse(value.split(/\s+/).first)
          return bad_value("price", value) if amount.nil?

          game.update!(price: amount)
          body = Pito::Copy.render_html(
            "pito.copy.price.updated",
            { game: game.title, price: Pito::Games::PriceGlyphs.html(game.price) },
            shimmer: [ :game ]
          )
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { "body" => body.to_s, "html" => true } }
          ])
        end

        def update_platform(game, value)
          # normalize titleizes free text deliberately (lenient platform entry,
          # same as the retired setter) — only a BLANK value is refused.
          normalized = Pito::Games::PlatformInput.normalize(value)
          return bad_value("platform", value) if normalized.blank?

          unless game.platforms.include?(normalized)
            game.update!(platforms: game.platforms + [ normalized ])
            GameEmbedIndexJob.perform_later(game.id)
          end
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system,
              payload: Pito::MessageBuilder::Game::PlatformSet.call(game, platform: normalized, removed: false) }
          ])
        end

        # ── vid fields (staged; the confirmation executes) ─────────────────────

        def update_vid(field, id, value)
          return usage unless VID_FIELDS.include?(field)

          video = ::Video.find_by(id: id)
          return not_found("vid ##{id}") unless video

          staged = field == "tags" ? value.split(",").map(&:strip).reject(&:blank?) : value
          return bad_value(field, value) if staged.blank?

          payload = Pito::MessageBuilder::Video::MetadataConfirmation.call(
            video, field:, value: staged, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: } ])
        end

        # ── replies ────────────────────────────────────────────────────────────

        def usage
          Pito::Chat::Result::Error.new(message_key: "pito.chat.update.usage", message_args: {})
        end

        def not_found(ref)
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.update.not_found", message_args: { ref: }
          )
        end

        def bad_value(field, value)
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.update.bad_value", message_args: { field:, value: }
          )
        end

        def ok_text(key, **args)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(key, **args) }
          ])
        end
      end
    end
  end
end
