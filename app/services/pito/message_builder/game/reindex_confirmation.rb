# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for a "reindex this game?" confirmation.
      #
      # Emitted when the user replies `#<handle> reindex` to a game-enhanced event.
      # The executor branch (`game_reindex` in Pito::Confirmation::Executor) calls
      # Game::VoyageIndexer.call(game, force: true) on confirm.
      module ReindexConfirmation
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(game, conversation:)
          payload = {
            "command"    => "game_reindex",
            "body"       => Pito::Copy.render("pito.copy.games.reindex_confirm", { title: game.title }),
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
