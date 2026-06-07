# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list games` messages (reply_target: "game_list").
      #
      # The list stamps each row with its game ID, so the user replies:
      #
      #   #<handle> show <id|title>  — append the P9 detail card for that game.
      #
      # Mode :append — adds a new message below; the list stays follow-up-able so
      # the user can `show` several games in turn. Unknown reference → a witty
      # not-found (appended). Invalid action → Result::Error.
      class GameList < Pito::FollowUp::Handler
        self.target "game_list"
        self.mode   :append
        self.actions "show", "delete"

        DELETE_ACTIONS = %w[delete rm].freeze

        def call(event:, rest:, conversation:) # rubocop:disable Lint/UnusedMethodArgument
          action, ref = parse_rest(rest)
          ref  = ref.to_s.strip
          game = resolve_game(ref)

          if action == "show"
            return not_found(ref) unless game

            Pito::FollowUp::Result::Append.new(events: [
              { kind: "system", payload: Pito::Game::DetailMessage.call(game, conversation:) }
            ])
          elsif DELETE_ACTIONS.include?(action)
            # Spawn the SAME delete confirmation as `delete game <id>`.
            return not_found(ref) unless game

            Pito::FollowUp::Result::Append.new(events: [
              { kind: "confirmation", payload: Pito::Game::DeleteConfirmation.call(game, conversation:) }
            ])
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_list.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        def resolve_game(ref)
          id = ref.delete_prefix("#")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Game.find_by("title ILIKE ?", ref)
        end

        def not_found(ref)
          Pito::FollowUp::Result::Append.new(events: [
            { kind: "system", payload: { text: Pito::Copy.render("pito.copy.games.not_found", { ref: ref }) } }
          ])
        end
      end
    end
  end
end
