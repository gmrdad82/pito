# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for a "resync this game?" confirmation.
      #
      # Emitted when the user replies `#<handle> resync` to a game-detail event.
      # The executor branch (`game_resync` in Pito::Confirmation::Executor) enqueues
      # GameIgdbSync on confirm.
      module ResyncConfirmation
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(game, conversation:)
          payload = {
            "command"         => "game_resync",
            "body"            => Pito::Copy.render("pito.copy.games.resync_confirm", { title: game.title }),
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
