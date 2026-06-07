# frozen_string_literal: true

# Handler for the `delete game <id|title>` / `rm game <id|title>` chat verb.
#
# Resolves a single game by **ID** (`#123`/`123`) or title (ILIKE) and emits a
# confirmation event (`command: "game_delete"`, follow-up-able `confirmation`).
# The destroy happens in `Pito::Confirmation::Executor` on `#<handle> confirm`.
# The game title is carried in the payload so the outcome text survives the row's
# deletion. Unknown reference → witty not-found; no reference → usage hint.
module Pito
  module Chat
    module Handlers
      class Delete < Pito::Chat::Handler
        self.verb = :delete
        self.description_key = "pito.chat.delete.descriptions.delete"

        NOUN_FILLERS = %w[game games].freeze

        def call
          ref = extract_ref
          return needs_ref if ref.blank?

          game = resolve_game(ref)
          return not_found(ref) unless game

          confirmation_event(game)
        end

        private

        def extract_ref
          message.body_tokens
                 .map(&:value)
                 .reject { |w| NOUN_FILLERS.include?(w.to_s.downcase) }
                 .join(" ")
                 .strip
        end

        def resolve_game(ref)
          id = ref.delete_prefix("#")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Game.find_by("title ILIKE ?", ref)
        end

        def confirmation_event(game)
          payload = Pito::Game::DeleteConfirmation.call(game, conversation:)
          Pito::Chat::Result::Ok.new(events: [ { kind: "confirmation", payload: payload } ])
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.delete.needs_ref", message_args: {})
        end

        def not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { text: Pito::Copy.render("pito.copy.games.not_found", { ref: ref }) } }
          ])
        end
      end
    end
  end
end
