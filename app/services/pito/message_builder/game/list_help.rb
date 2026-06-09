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
      # Column tokens (aliases) are derived from ListColumns::COLUMNS so they
      # never drift from the parser vocabulary; all user-facing strings come from
      # Pito::Copy.
      module ListHelp
        class << self
          # @return [Hash] system payload ({ html: true, body: <pre block> })
          def call
            groups = [
              [ c("options_title"), option_rows ],
              [ c("columns_title"), column_rows ]
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

          # [token, description] pairs for the Columns group — tokens are the
          # real parser aliases, descriptions come from copy keyed by canonical.
          def column_rows
            ListColumns::COLUMNS.map do |canonical, cfg|
              [ cfg[:aliases].join(", "), c("col_#{canonical}_desc") ]
            end
          end

          def c(key) = Pito::Copy.render("pito.copy.list.games_help.#{key}")
        end
      end
    end
  end
end
