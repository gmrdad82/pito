# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the ENHANCED video message — a placeholder intro
      # rendered by the EnhancedComponent typewriter path.
      #
      # Streamed after `show video <ref>`. Rendered as `kind: :enhanced`
      # (the pito-blue chrome) and is NOT follow-up-able — only the standard
      # detail message carries a #handle.
      #
      # Analytics/stats are a later feature; this emits a plain body line via
      # Pito::Copy so the enhanced slot is visually present from day one.
      module Enhanced
        module_function

        # @param video [::Video]
        # @return [Hash] enhanced event payload (body string, no html key).
        def call(video)
          { "body" => Pito::Copy.render("pito.copy.video.enhanced_placeholder", { title: video.title }) }
        end
      end
    end
  end
end
