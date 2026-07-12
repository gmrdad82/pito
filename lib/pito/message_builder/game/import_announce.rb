# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the :system "announce" payload for import/resync flows.
      # Shared between GameImportJob (:import + :resync) and GameIgdbSync (:resync).
      #
      # The timestamp rides a leading ts-slot so it sits on the SAME row as the copy.
      #   :import  → present-tense "importing…" (pito.copy.games.importing), title
      #              subject-shimmered, NO id shown (import still in progress; 19.2).
      #   :resync  → "re-synced" (pito.copy.games.announce), title + id.
      module ImportAnnounce
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game         [::Game]
        # @param action       [Symbol] :import | :resync
        # @param conversation [Conversation]  (unused; kept for API symmetry with ImportDone)
        # @return [Hash] system event payload (body html + html: true + game_id)
        def call(game, action:, conversation: nil) # conversation reserved for API symmetry with ImportDone
          intro =
            if action == :resync
              Pito::Copy.render_html(
                "pito.copy.games.announce",
                { title: game.title, id: "##{game.id}", verb: "re-synced" },
                shimmer: [ :title ], reference: [ :id ]
              )
            else
              # Import IN PROGRESS (19.2): present-tense "importing…", NO id shown
              # (steps 3–5 still run; the id lands on the done message).
              Pito::Copy.render_html(
                "pito.copy.games.importing",
                { title: game.title },
                shimmer: [ :title ]
              )
            end
          # Leading ts-slot → the timestamp sits on the SAME row as the copy (19.2).
          body = %(<div class="text-fg"><span data-pito-ts-slot></span>#{intro}</div>)
          html_payload(body: body, game_id: game.id)
        end
      end
    end
  end
end
