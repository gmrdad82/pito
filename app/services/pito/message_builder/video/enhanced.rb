# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the ENHANCED video message — a placeholder intro
      # rendered by the EnhancedComponent (the pito-blue chrome).
      #
      # Streamed after `show video <ref>` as `kind: :enhanced`, and NOT
      # follow-up-able — only the standard detail message carries a #handle.
      #
      # Analytics/stats are a later feature; for now this emits an HTML body (the
      # Enhanced slot always renders HTML, like the game recommendations card) so
      # the slot is visually present + styled from day one.
      module Enhanced
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param video [::Video]
        # @return [Hash] enhanced event payload (html body).
        def call(video)
          intro = Pito::Copy.render("pito.copy.video.enhanced_placeholder", { title: video.title })
          html_payload(
            body: %(<span class="pito-video-enhanced-message text-fg">#{ERB::Util.html_escape(intro)}</span>)
          )
        end
      end
    end
  end
end
