# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the `platform <game> <name>` confirmation (and the
      # equivalent `#<handle> platform <name>` follow-up).
      #
      # Emits a :system message whose HTML body confirms the platform that was
      # appended, with the game's platform logo(s) rendered inline via
      # Pito::Games::PlatformTokens.icons_html. When the newly-set platform has no
      # logo family (e.g. "Xbox"), the unknown-platform note is used instead and
      # no logo is shown for it.
      module PlatformSet
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game     [::Game]  the game whose platforms were updated.
        # @param platform [String]  the normalized platform string that was set/removed.
        # @param removed  [Boolean] true when the platform was REMOVED (unset).
        # @return [Hash] system event payload (body html + html: true + game_id).
        def call(game, platform:, removed: false)
          title = ERB::Util.html_escape(game.title)
          plat  = ERB::Util.html_escape(platform)
          known = Pito::Games::PlatformTokens.tokens([ platform ]).any?

          key =
            if removed
              "pito.copy.games.platform_unset"
            elsif known
              "pito.copy.games.platform_set"
            else
              "pito.copy.games.platform_unknown"
            end
          text  = Pito::Copy.render(key, { title: title, platform: plat })
          icons = Pito::Games::PlatformTokens.icons_html(game.platforms)

          body = %(<span class="text-fg-dim">#{text}</span> #{icons}).strip
          html_payload(body: body, game_id: game.id)
        end
      end
    end
  end
end
