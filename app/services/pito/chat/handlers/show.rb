# frozen_string_literal: true

# Handler for the `show game <id|title>` chat verb.
#
# Resolves a single game by **ID** (`#123` or `123`) or title (ILIKE) and emits
# the P9 detail message (`Pito::Game::DetailMessage`, follow-up-able `game_detail`).
# Unknown reference → witty not-found via `Pito::Copy`. No reference → a usage
# hint (the no-arg picker fast-path is wired in `ChatController`, T10.10).
module Pito
  module Chat
    module Handlers
      class Show < Pito::Chat::Handler
        self.verb = :show
        self.description_key = "pito.chat.show.descriptions.show"

        # `game`/`games` are noun fillers the user types but that carry no value.
        NOUN_FILLERS = %w[game games].freeze

        def call
          ref = extract_ref
          return needs_ref if ref.blank?

          game = resolve_game(ref)
          return not_found(ref) unless game

          # Mirror an import: the Standard detail message (follow-up-able) plus the
          # Enhanced recommendations message (pito chrome, not follow-up-able).
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system,   payload: Pito::MessageBuilder::Game::Detail.call(game, conversation:) },
            { kind: :enhanced, payload: Pito::MessageBuilder::Game::Enhanced.call(game) }
          ])
        end

        private

        def extract_ref
          message.body_tokens
                 .map(&:value)
                 .reject { |w| NOUN_FILLERS.include?(w.to_s.downcase) }
                 .join(" ")
                 .strip
        end

        # ID form (`#5`/`5`/`# 5`) → find by id; otherwise case-insensitive title.
        # The lexer splits `#9` into `#` + `9`, so the joined ref can be `# 9` —
        # strip a leading `#` plus any whitespace before the digit check.
        def resolve_game(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Game.find_by("title ILIKE ?", ref)
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.show.needs_ref", message_args: {})
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
