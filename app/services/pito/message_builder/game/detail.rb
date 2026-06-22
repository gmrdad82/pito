# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload Hash for a game-detail system event.
      #
      # Returns a Hash shaped for a system event (body + html: true) with
      # follow-up fields injected by Pito::FollowUp.make_followupable!.
      #
      # == Usage
      #
      #   payload = Pito::MessageBuilder::Game::Detail.call(game, conversation: conv)
      #   # => { "body" => "<div>...</div>", "html" => true, "reply_handle" => ..., "reply_target" => "game_detail" }
      #
      module Detail
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game         [::Game]         the game record to render.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] system event payload with body, html: true, and follow-up fields.
        def call(game, conversation:)
          intro = Pito::Copy.render_html("pito.copy.game.detail_intro", { title: game.title }, shimmer: [ :title ])

          # The intro + timestamp live INSIDE the card's left column (above the
          # cover, capped to the cover width) so the right column starts at the
          # top beside them. The component embeds a ts-slot the event component
          # fills with the "HH:MM ·" timestamp.
          body = render_component(Pito::Game::DetailComponent.new(game: game, intro: intro))

          payload = html_payload(body: body, game_id: game.id)

          Pito::FollowUp.make_followupable!(payload, target: "game_detail", conversation: conversation)

          payload
        end
      end
    end
  end
end
