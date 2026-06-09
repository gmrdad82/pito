# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builder for the `list games --help` system message.
      #
      # Produces a System payload with:
      #   body         — intro line from copy
      #   table_heading — ["Option", "Aliases"]
      #   table_rows    — one row per optional column, using :cells for two-column layout
      #
      # Column data is derived from Pito::MessageBuilder::Game::ListColumns::COLUMNS
      # so aliases always stay in sync with the actual parser vocabulary.
      module ListHelp
        class << self
          # @return [Hash] system payload for `list games --help`
          def call
            {
              "body"          => Pito::Copy.render("pito.copy.list.games_help.intro"),
              "table_heading" => [
                Pito::Copy.render("pito.copy.list.games_help.option_heading"),
                Pito::Copy.render("pito.copy.list.games_help.aliases_heading")
              ],
              "table_rows"    => build_rows
            }
          end

          private

          def build_rows
            Pito::MessageBuilder::Game::ListColumns::COLUMNS.map do |_canonical, cfg|
              label   = cfg[:heading]
              aliases = cfg[:aliases].join(", ")
              {
                cells: [
                  { text: label,   class: "text-cyan whitespace-nowrap" },
                  { text: aliases, class: "text-fg-dim" }
                ]
              }
            end
          end
        end
      end
    end
  end
end
