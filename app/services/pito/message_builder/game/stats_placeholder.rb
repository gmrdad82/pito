# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the Stats & Analytics PLACEHOLDER enhanced message.
      #
      # Streamed after `show game <ref>` as `kind: :enhanced`, positioned between
      # the linked-videos list and the recommendations card. Analytics/stats are a
      # later feature; this emits a styled HTML span so the slot is present from
      # day one.
      #
      # NOT follow-up-able — only the detail message carries a #handle.
      module StatsPlaceholder
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game [::Game]
        # @return [Hash] enhanced event payload (html body).
        def call(game)
          intro = Pito::Copy.render("pito.copy.game.stats_placeholder", { title: game.title })
          html_payload(
            body: %(<span class="pito-game-stats-placeholder-message text-fg">#{ERB::Util.html_escape(intro)}</span>)
          )
        end
      end
    end
  end
end
