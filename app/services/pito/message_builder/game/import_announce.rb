# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the :system "announce" payload for import/resync flows.
      # Shared between GameImportJob (:import + :resync) and GameIgdbSync (:resync).
      #
      # Emits a shimmered intro: title (purple subject shimmer) + id (cyan reference token).
      # The `action` kwarg drives the %{verb} placeholder:
      #   :import  → "imported"
      #   :resync  → "re-synced"
      module ImportAnnounce
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game         [::Game]
        # @param action       [Symbol] :import | :resync
        # @param conversation [Conversation]  (unused; kept for API symmetry with ImportDone)
        # @return [Hash] system event payload (body html + html: true + game_id)
        def call(game, action:, conversation: nil) # conversation reserved for API symmetry with ImportDone
          verb  = action == :resync ? "re-synced" : "imported"
          intro = Pito::Copy.render_html(
            "pito.copy.games.announce",
            { title: game.title, id: "##{game.id}", verb: verb },
            shimmer:   [ :title ],
            reference: [ :id ]
          )
          body = %(<div class="text-fg">#{intro}</div>)
          html_payload(body: body, game_id: game.id)
        end
      end
    end
  end
end
