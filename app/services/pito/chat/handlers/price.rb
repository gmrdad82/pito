# frozen_string_literal: true

# Handler for the `price` chat verb (two subcommands).
#
# `price set <id> <amount>` — sets a game's euro price (the nullable
# `games.price` decimal column). The amount is parsed with BigDecimal, rounded
# to 2 decimals, and must be strictly positive. Resolves the game by numeric ID
# only (`123` / `#123`); unknown/non-numeric ref → witty not-found.
#
# `price unset <id>` — clears the price back to NULL ("unpriced").
#
# `price <id> <amount>` — implicit set (no subcommand word), at parity with the
# game-card reply `#<handle> price <amount>`. `set` stays accepted + explicit.
#
# Bare `price` / missing args → a usage hint naming the forms. The success event
# is a Standard `:system` message (witty confirmation).
module Pito
  module Chat
    module Handlers
      class Price < Pito::Chat::Handler
        self.verb = :price
        self.description_key = "pito.chat.price.descriptions.price"

        SET_SUBCOMMAND   = "set"
        UNSET_SUBCOMMAND = "unset"

        def call
          # The typed setter moved to the consolidated `update` verb; reply
          # forms (`#g3 price 20`, list-scoped `price <id> <amount>`) still
          # delegate here through the follow-up pipeline and are unchanged.
          return moved unless follow_up?

          subcommand, ref, raw_amount = parse_args

          case subcommand
          when SET_SUBCOMMAND   then set(ref, raw_amount)
          when UNSET_SUBCOMMAND then unset(ref)
          else
            # Implicit set: `price <id> <amount>` (no subcommand) — `subcommand` holds the
            # id, `ref` the amount. Parity with the `#<handle> price <amount>` reply.
            set(subcommand, ref)
          end
        end

        private

        def moved
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.update.moved",
            message_args: { example: "update game price 12 59.99" }
          )
        end

        # `price set <id> <amount>` — resolve the game, parse the amount, save.
        def set(ref, raw_amount)
          return needs_ref unless ref.present? && raw_amount.present?

          game = resolve_game(ref)
          return not_found(ref) unless game

          amount = parse_amount(raw_amount)
          return needs_ref if amount.nil?

          game.update!(price: amount)
          updated(game)
        end

        # `price unset <id>` — resolve the game, clear the price to NULL.
        def unset(ref)
          return needs_ref unless ref.present?

          game = resolve_game(ref)
          return not_found(ref) unless game

          game.update!(price: nil)
          unset_confirmation(game)
        end

        # Strip the verb, then split into the subcommand word, game ref, and the
        # amount token. Trailing tokens beyond the amount are ignored.
        def parse_args
          rest = message.raw.to_s.strip.sub(/\Aprice\b\s*/i, "").strip
          subcommand, ref, raw_amount = rest.split(/\s+/, 3)
          [ subcommand&.downcase, ref, raw_amount&.split(/\s+/)&.first ]
        end

        # Parse the euro amount via the shared Pito::Games::PriceAmount parser
        # (exact BigDecimal rounded to 2 decimals; non-negative, 0 = free; nil for
        # non-numeric / negative). One canonical parse across the verb, its reply,
        # and the `:price_amount` resolver.
        def parse_amount(raw)
          Pito::Games::PriceAmount.parse(raw)
        end

        # Numeric ID only: strip optional leading `#`, require `\A\d+\z`.
        def resolve_game(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          nil
        end

        def updated(game)
          # Render the price as the Pito::Coin glyph run (coins / free-star + the
          # number) — the same at-a-glance currency the game card + list use — not a
          # bare "€59.99". PriceGlyphs.html is html_safe, so it survives render_html's
          # escaping (img tags intact); the game title gets the subject shimmer.
          body = Pito::Copy.render_html(
            "pito.copy.price.updated",
            { game: game.title, price: Pito::Games::PriceGlyphs.html(game.price) },
            shimmer: [ :game ]
          )
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { "body" => body.to_s, "html" => true } }
          ])
        end

        def unset_confirmation(game)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(
              "pito.copy.price.unset", game: game.title
            ) }
          ])
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.price.needs_ref", message_args: {})
        end

        def not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end
      end
    end
  end
end
