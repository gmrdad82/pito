# frozen_string_literal: true

# Handler for the `footage` chat tool (one subcommand).
#
# `footage update <id> <hours>` — sets a game's total recorded footage (the
# per-game `games.footage_hours` decimal column, stored in hours, in 0.5 steps).
# Resolves the game by **numeric ID only** (`123` / `#123`); unknown/non-numeric
# reference → witty not-found. Missing/short args → a usage hint pointing at the
# full form. Hours are parsed with BigDecimal for exactness and rounded UP to the
# next half-hour, so any positive value lands on a clean 0.5 step. The success
# event is a Standard `:system` message confirming the new total.
#
# The `footage snippet` / `footage game <id>` ffprobe one-liner was removed
# (2026-07-13) — that flow now lives in pito-tui (ctrl+f), which runs locally
# where ffprobe lives.
#
# Bare `footage` / an unknown subcommand → a usage hint naming the surviving form.
module Pito
  module Chat
    module Handlers
      class Footage < Pito::Chat::Handler
        self.tool = :footage
        self.description_key = "pito.chat.footage.descriptions.footage"

        SUBCOMMAND = "update"

        def call
          subcommand, ref, raw_hours = parse_args

          case subcommand
          when SUBCOMMAND then follow_up? ? update(ref, raw_hours) : moved
          else needs_ref
          end
        end

        private

        # The typed setter moved to the consolidated `update` tool; the reply
        # form (`#g3 footage 2.5`) is unchanged.
        def moved
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.update.moved",
            message_args: { example: "update game footage 12 8.5" }
          )
        end

        # `footage update <id> <hours>` — resolve the game, ceil the hours, save.
        def update(ref, raw_hours)
          return needs_ref unless ref.present? && raw_hours.present?

          game = resolve_game(ref)
          return not_found(ref) unless game

          hours = parse_hours(raw_hours)
          return needs_ref if hours.nil?

          game.update!(footage_hours: hours)
          confirmation(game, hours)
        end

        # `footage update <id> <hours>` — strip the tool, then split into the
        # subcommand word, the game ref, and the hours token. Trailing tokens
        # beyond the hours value are ignored.
        def parse_args
          rest = message.raw.to_s.strip.sub(/\Afootage\b\s*/i, "").strip
          subcommand, ref, raw_hours = rest.split(/\s+/, 3)
          [ subcommand&.downcase, ref, raw_hours&.split(/\s+/)&.first ]
        end

        # Parse the hours value via the shared Pito::Games::FootageAmount parser
        # (exact BigDecimal, ceil UP to the next 0.5 → Rational; nil for
        # non-numeric / negative). One canonical parse across the tool, its reply,
        # and the `:footage_hours` resolver.
        def parse_hours(raw)
          Pito::Games::FootageAmount.parse(raw)
        end

        # Numeric ID only: strip optional leading `#`, require `\A\d+\z`.
        # Any non-numeric ref → nil (→ witty not-found).
        def resolve_game(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          nil
        end

        def confirmation(game, hours)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(
              "pito.copy.footage.updated", game: game.title, hours: format_hours(hours)
            ) }
          ])
        end

        # Render an exact half-step total as "12.5h" / "5h".
        def format_hours(hours)
          format("%gh", hours.to_f)
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.footage.needs_ref", message_args: {})
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
