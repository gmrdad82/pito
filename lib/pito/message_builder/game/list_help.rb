# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builder for the `list games --help` system message.
      #
      # Renders an `nvim --help`-style man page: a `Usage:` line, an `Options:`
      # group, and a `Columns:` group, each row being a left-aligned token padded
      # to a common width followed by its description. The whole block is one
      # `html: true` body inside a `.pito-help-block` (white-space: pre-wrap) so
      # the monospace alignment is preserved.
      #
      # Column and filter tokens + descriptions are DERIVED from the config
      # capability vocabulary (`Pito::Grammar::Capability`) — the single grammar
      # `--help`, MCP, and autocomplete all read — so they can never drift from the
      # parser vocabulary. Add a column/filter to tools.yml `capabilities:` and it
      # appears here automatically; the usage/options wording stays in Pito::Copy.
      module ListHelp
        NOUN = "games"

        class << self
          # @return [Hash] system payload ({ html: true, body: <pre block> })
          def call
            groups = [
              [ c("options_title"), option_rows ],
              [ c("columns_title"), column_rows ],
              [ c("filters_title"), filter_rows ]
            ]
            body = Pito::MessageBuilder::ManPage.render(usage: c("usage"), groups:)
            { "html" => true, "body" => body }
          end

          private

          # [token, description] pairs for the Options group.
          def option_rows
            [
              [ c("opt_with"),   c("opt_with_desc") ],
              [ c("opt_sorted"), c("opt_sorted_desc") ],
              [ c("opt_help"),   c("opt_help_desc") ]
            ]
          end

          # [token, description] rows from the config capability set — tokens are the
          # real parser aliases (canonical first), descriptions resolve the config
          # `desc` copy key, so the list never drifts from the actual grammar.
          def column_rows
            Pito::Grammar::Capability.public_columns(:list, NOUN).map do |col|
              [ col.tokens.join(", "), Pito::Copy.render(col.desc) ]
            end
          end

          def filter_rows
            Pito::Grammar::Capability.filters(:list, NOUN).map do |filter|
              # A vocabulary-backed filter has no literal tokens — show its name
              # (the desc copy carries example values) rather than a blank cell.
              tokens = filter.tokens.any? ? filter.tokens : [ filter.name ]
              [ tokens.join(", "), Pito::Copy.render(filter.desc) ]
            end
          end

          def c(key) = Pito::Copy.render("pito.copy.list.games_help.#{key}")
        end
      end
    end
  end
end
