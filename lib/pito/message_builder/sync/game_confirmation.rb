# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for a "sync this game from IGDB?" confirmation.
      # Mirrors VideosConfirmation: a follow-up-able confirmation whose executor
      # branch (`sync_game` in Pito::Confirmation::Executor) enqueues SyncGameJob
      # on confirm.
      module GameConfirmation
        module_function

        # @param game         [::Game]       the game to re-sync from IGDB.
        # @param conversation [Conversation]
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
