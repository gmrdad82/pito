# frozen_string_literal: true

# Handler for the `footage <id|title> <path>` chat verb.
#
# Resolves a game by **ID** (`#123`/`123`) or **title** (ILIKE) and a footage
# folder path, then emits a Standard message containing the exact, copyable
# `bin/rails pito:tools:probe …` command (Pito::Footage::ProbeCommandComponent).
# Shared with the `#<handle> footage <path>` follow-up (Pito::FollowUp::Handlers::
# GameDetail) — same FootageImport builder, different dispatch.
# Unknown reference → witty not-found. Missing ref/path → usage hint.
module Pito
  module Chat
    module Handlers
      class Footage < Pito::Chat::Handler
        self.verb = :footage
        self.description_key = "pito.chat.footage.descriptions.footage"

        def call
          ref, path = parse_args
          return needs_ref if ref.blank? || path.blank?

          game = resolve_game(ref)
          return not_found(ref) unless game

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Game::FootageImport.call(game, path: path) }
          ])
        end

        private

        # `footage <ref> <path>` — the path is the tail starting at the first
        # absolute (`/…`) or home (`~/…`) token, so a multi-word title before it
        # stays whole (e.g. `footage Ghosts n Goblins /mnt/clips`). No path token →
        # everything is the ref (and we ask for a path).
        def parse_args
          rest = message.raw.to_s.strip.sub(/\Afootage\b\s*/i, "").strip
          if (m = rest.match(%r{\s+([~/].*)\z}))
            [ rest[0...m.begin(0)].strip, m[1].strip ]
          else
            [ rest, nil ]
          end
        end

        # ID form (`#5`/`5`/`# 5`) → find by id; otherwise case-insensitive title.
        def resolve_game(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Game.find_by("title ILIKE ?", ref)
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
