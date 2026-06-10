# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the `import <game> <path>` command (and the
      # equivalent `#<handle> import <path>` follow-up) response.
      #
      # Emits a Standard (:system) message containing a witty probe-prompt line
      # followed by the copyable, ready-to-run `pito:tools:probe` command for the
      # given game + footage folder (Pito::Footage::ProbeCommandComponent).
      module FootageImport
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param game  [::Game]
        # @param path  [String] absolute footage folder the command will probe.
        # @param force [Boolean] when true, the snippet re-probes + overwrites
        #   already-imported files (emits `-- --force`).
        # @return [Hash] system event payload (body html + html: true + game_id).
        def call(game, path:, force: false)
          intro = Pito::Copy.render("pito.copy.footage.probe_prompt")
          snippet = render_component(Pito::Footage::ProbeCommandComponent.new(game_id: game.id, path: path, force: force))
          body = %(<p class="text-fg-dim">#{intro}</p>#{snippet})
          html_payload(body: body, game_id: game.id)
        end
      end
    end
  end
end
