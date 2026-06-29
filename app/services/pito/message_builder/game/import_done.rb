# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the :enhanced "done" payload for the import flow.
      # Emits 3 rows:
      #   1. Ironic+witty intro with shimmered title + cyan id reference token.
      #   2. "A new adventure awaits." (or similar from copy pool).
      #   3. "Type `show game` to see it in full." (or similar from copy pool).
      # Repliable with reply_target: "game_imported" (show-only).
      module ImportDone
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game         [::Game]
        # @param conversation [Conversation]
        # @return [Hash] enhanced event payload (body html + html: true + game_id + follow-up fields)
        def call(game, conversation:)
          intro     = Pito::Copy.render_html(
            "pito.copy.games.import_done.intro",
            { title: game.title, id: "##{game.id}" },
            shimmer:   [ :title ],
            reference: [ :id ]
          )
          adventure = Pito::Copy.render("pito.copy.games.import_done.adventure")
          see_it    = Pito::Copy.render("pito.copy.games.import_done.see_it")

          body = [
            %(<div class="text-fg">#{intro}</div>),
            %(<div class="text-fg">#{ERB::Util.html_escape(adventure)}</div>),
            %(<div class="text-fg">#{ERB::Util.html_escape(see_it)}</div>)
          ].join

          payload = html_payload(body: body, game_id: game.id)
          Pito::FollowUp.make_followupable!(payload, target: "game_imported", conversation: conversation)
          payload
        end
      end
    end
  end
end
