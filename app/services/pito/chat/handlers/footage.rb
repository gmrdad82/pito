# frozen_string_literal: true

# Handler for the `footage` chat verb (two subcommands).
#
# `footage update <id> <hours>` — sets a game's total recorded footage (the
# per-game `games.footage_hours` decimal column, stored in hours, in 0.5 steps).
# Resolves the game by **numeric ID only** (`123` / `#123`); unknown/non-numeric
# reference → witty not-found. Missing/short args → a usage hint pointing at the
# full form. Hours are parsed with BigDecimal for exactness and rounded UP to the
# next half-hour, so any positive value lands on a clean 0.5 step. The success
# event is a Standard `:system` message confirming the new total.
#
# `footage snippet` — renders a copyable shell one-liner the user runs in their
# footage folder; it ffprobes the current folder, ceils each file UP to 0.5h,
# sums them, prints the 1-decimal total, and copies it via `wl-copy`. The user
# then pastes that number into `footage update <id> <hours>`.
#
# Bare `footage` / an unknown subcommand → a usage hint naming both forms.
module Pito
  module Chat
    module Handlers
      class Footage < Pito::Chat::Handler
        self.verb = :footage
        self.description_key = "pito.chat.footage.descriptions.footage"

        SUBCOMMAND         = "update"
        SNIPPET_SUBCOMMAND = "snippet"

        def call
          sub, ref, raw_hours = parse_args

          case sub
          when SUBCOMMAND         then update(ref, raw_hours)
          when SNIPPET_SUBCOMMAND then snippet
          else needs_ref
          end
        end

        private

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

        # `footage snippet` — a Standard :system message rendering the copyable
        # one-liner component (with the inline first-line timestamp slot).
        def snippet
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Footage::Snippet.call }
          ])
        end

        # `footage update <id> <hours>` — strip the verb, then split into the
        # subcommand word, the game ref, and the hours token. Trailing tokens
        # beyond the hours value are ignored.
        def parse_args
          rest = message.raw.to_s.strip.sub(/\Afootage\b\s*/i, "").strip
          sub, ref, raw_hours = rest.split(/\s+/, 3)
          [ sub&.downcase, ref, raw_hours&.split(/\s+/)&.first ]
        end

        # Parse the hours value with BigDecimal (exact, not Float), then ceil UP
        # to the next 0.5 using integer math. Returns an exact Rational, or nil
        # for non-numeric / negative input.
        def parse_hours(raw)
          value = BigDecimal(raw.to_s)
          return nil if value.negative?

          half_units = (value * 2).ceil # BigDecimal#ceil → Integer
          half_units / 2r               # exact Rational on a clean 0.5 step
        rescue ArgumentError, TypeError
          nil
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
