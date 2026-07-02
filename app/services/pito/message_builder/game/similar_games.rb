# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the SIMILAR GAMES recommendations message —
      # the similar-games strip rendered by Pito::Games::SimilarGamesComponent.
      #
      # Streamed by `show game <ref>` as a standalone :enhanced card.
      # Stamped follow-up-able (reply_target: "game_similar") so the user can
      # reply `#<handle> show <id>` to drill into a similar game.
      module SimilarGames
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] event payload (body html + html: true + game_id + follow-up fields).
        def call(game, conversation:)
          body    = render_component(Pito::Games::SimilarGamesComponent.new(game: game))
          payload = html_payload(body: body, game_id: game.id)
          Pito::FollowUp.make_followupable!(payload, target: "game_similar", conversation:)
          payload
        end
      end
    end
  end
end
