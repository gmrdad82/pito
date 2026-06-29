# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the CHANNEL MATCHES recommendations message —
      # the channel-matches grid rendered by Pito::Game::ChannelsComponent.
      #
      # Streamed by `show game <ref>` as a standalone :enhanced card.
      # Stamped follow-up-able (reply_target: "game_channels") so the user can
      # reply `#<handle> show @<handle>` to drill into a matched channel.
      module Channels
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] event payload (body html + html: true + game_id + follow-up fields).
        def call(game, conversation:)
          body    = render_component(Pito::Game::ChannelsComponent.new(game: game))
          payload = html_payload(body: body, game_id: game.id)
          Pito::FollowUp.make_followupable!(payload, target: "game_channels", conversation:)
          payload
        end
      end
    end
  end
end
