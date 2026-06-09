# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for a "sync this game from IGDB?" confirmation.
      # The executor branch (`sync_game` in Pito::Confirmation::Executor) enqueues
      # SyncGameJob on confirm, which calls IGDB + broadcasts the summary.
      module SyncConfirmation
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(game, conversation:)
          payload = {
            "command"         => "sync_game",
            "body"            => Pito::Copy.render("pito.copy.sync.game_confirm", { title: game.title }),
            "html"            => false,
            "game_id"         => game.id,
            "game_title"      => game.title,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
