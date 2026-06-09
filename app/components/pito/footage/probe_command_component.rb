# frozen_string_literal: true

module Pito
  module Footage
    # Renders a copyable `pito:tools:probe` command snippet.
    #
    # Usage:
    #   <%= render Pito::Footage::ProbeCommandComponent.new(game_id: game.id) %>
    #
    # Clicking the block copies the command via the `pito--footage-import`
    # Stimulus controller. Alt+C copies the most recent import block globally.
    class ProbeCommandComponent < ApplicationComponent
      def initialize(game_id:, path:)
        @game_id = game_id
        @path    = path.to_s.chomp("/")
      end

      # The exact command to run from the pito home dir — probes every mp4/mkv/mov
      # in the folder (the rake task filters by extension) and attaches them to
      # the game. The `/*` glob is expanded by the task's Dir.glob.
      def command_text
        %(bin/rails pito:tools:probe game=#{@game_id} path="#{@path}/*")
      end

      def feedback_variants_json
        I18n.t("pito.copy.footage.copied").to_json
      end
    end
  end
end
