# frozen_string_literal: true

module Pito
  module Footage
    # Renders a copyable `pito:tools:probe` command snippet.
    #
    # Usage:
    #   <%= render Pito::Footage::ProbeCommandComponent.new(game_id: game.id) %>
    #
    # Clicking the block (or pressing Ctrl+C while focused) copies the
    # command to the clipboard via the `clipboard` Stimulus controller.
    class ProbeCommandComponent < ApplicationComponent
      def initialize(game_id:, path: nil)
        @game_id = game_id
        @path = path || default_path
      end

      def command_text
        %(cd #{@path} && rails pito:tools:probe game=#{@game_id} path="*")
      end

      private

      def default_path
        I18n.t("pito.footage.probe_command.default_path")
      end
    end
  end
end
