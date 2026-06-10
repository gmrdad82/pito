# frozen_string_literal: true

# Handler for the `footage game <id> <path>` chat verb.
#
# Resolves a game by **numeric ID only** (`123` / `#123`) and a footage
# folder path, then emits a Standard message containing the exact, copyable
# `bin/rails pito:tools:probe …` command (Pito::Footage::ProbeCommandComponent).
# Shared with the `#<handle> footage <path>` follow-up (Pito::FollowUp::Handlers::
# GameDetail) — same FootageImport builder, different dispatch.
# Unknown/non-numeric reference → witty not-found. Missing ref/path → usage hint.
module Pito
  module Chat
    module Handlers
      class Footage < Pito::Chat::Handler
        self.verb = :footage
        self.description_key = "pito.chat.footage.descriptions.footage"

        def call
          ref, path, force = parse_args
          return needs_ref if ref.blank? || path.blank?

          game = resolve_game(ref)
          return not_found(ref) unless game

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Game::FootageImport.call(game, path: path, force: force) }
          ])
        end

        private

        # `footage game <id> [--force] <path>` — strip the verb, then an optional
        # `game` noun filler (like other handlers accept), leaving `<id> <path>`.
        # An optional `--force` (or bare `force`) flag re-probes + overwrites
        # already-imported footage; it may sit before the path or trail the line,
        # never inside the path. The path is the tail starting at the first
        # absolute (`/…`) or home (`~/…`) token. No path token → everything is the
        # ref (ask for a path).
        def parse_args
          rest = message.raw.to_s.strip.sub(/\Afootage\b\s*/i, "").strip
          rest = rest.sub(/\Agame\b\s*/i, "").strip

          # Trailing `--force` / `force` (after the path) — strip before splitting.
          force = !rest.sub!(/\s+(?:--)?force\b\s*\z/i, "").nil?

          if (m = rest.match(%r{\s+([~/].*)\z}))
            head = rest[0...m.begin(0)].to_s
            path = m[1].strip
          else
            head = rest
            path = nil
          end

          # `--force` / `force` in the head (leading or between the id and path).
          if head.match?(/(?:\A|\s)(?:--)?force\b/i)
            force = true
            head  = head.gsub(/(?:\A|\s)(?:--)?force\b/i, " ").strip.squeeze(" ")
          end

          [ head, path, force ]
        end

        # Numeric ID only: strip optional leading `#`, require `\A\d+\z`.
        # Any non-numeric ref → nil (→ witty not-found).
        def resolve_game(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          nil
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
