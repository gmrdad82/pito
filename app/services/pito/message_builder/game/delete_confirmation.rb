# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for a "delete this game?" confirmation, shared by the
      # `delete game <id>` chat verb and the `#<handle> delete <id>` game-list
      # follow-up so both spawn the IDENTICAL confirmation dialog. The destroy
      # happens in Pito::Confirmation::Executor on `#<handle> confirm`.
      module DeleteConfirmation
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(game, conversation:)
          payload = {
            "command"    => "game_delete",
            "body"       => Pito::Copy.render("pito.copy.games.delete_confirm", { title: game.title }),
            "html"       => false,
            "game_id"    => game.id,
            "game_title" => game.title
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
