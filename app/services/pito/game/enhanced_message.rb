# frozen_string_literal: true

module Pito
  module Game
    # Builds the payload for the ENHANCED game message — the recommendations
    # card (channel matches + similar games) rendered by Pito::Game::EnhancedComponent.
    #
    # Streamed both after an import (GameImportJob) and after `show game <ref>`.
    # Rendered as `kind: :enhanced` (the pito-blue chrome) and is NOT
    # follow-up-able — only the standard detail message carries a #handle.
    module EnhancedMessage
      module_function

      # @param game [::Game]
      # @return [Hash] system event payload (body html + html: true + game_id).
      def call(game)
        body = ApplicationController.renderer.render(
          Pito::Game::EnhancedComponent.new(game: game),
          layout: false
        )

        {
          "body"    => body,
          "html"    => true,
          "game_id" => game.id
        }
      end
    end
  end
end
