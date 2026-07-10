# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builder for the `list channels --help` system message.
      #
      # Renders an nvim-style man page via ManPage: a `Usage:` line and an
      # `Options:` group. Mirrors Game::ListHelp / Video::ListHelp — everything
      # lives inside the single `.pito-help-block` div produced by ManPage.render.
      #
      # The base table columns are always shown; `with likes` / `without likes`
      # add or drop the addable audience column (G26.2), and `sorted by
      # <column> [desc]` works on every column except Avatar (an addable
      # column sorts while visible) — the Options group lists with/without,
      # sort, and --help.
      #
      # The columns section is DERIVED from the config capability vocabulary
      # (`Pito::Grammar::Capability`) — the single grammar `--help`, MCP, and
      # autocomplete all read — so it never drifts from the parser vocabulary. The
      # usage/options wording stays in Pito::Copy (`pito.copy.list.channels_help.*`).
      # Channels carry no filters, so there is no Filters group.
      module ListHelp
        NOUN = "channels"

        class << self
          # @return [Hash] system payload ({ "html" => true, "body" => <pre block> })
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
              [ c("opt_with"), c("opt_with_desc") ],
              [ c("opt_without"), c("opt_without_desc") ],
              [ c("opt_sort"), c("opt_sort_desc") ],
              [ c("opt_help"), c("opt_help_desc") ]
            ]
          end

          # [token, description] rows from the config capability set (subs/views/
          # vids default-on, likes addable) — descriptions resolve the config `desc`
          # copy key, so the columns never drift from the actual grammar.
          def column_rows
            Pito::Grammar::Capability.public_columns(:list, NOUN).map do |col|
              [ col.tokens.join(", "), Pito::Copy.render(col.desc) ]
            end
          end

          def c(key) = Pito::Copy.render("pito.copy.list.channels_help.#{key}")
        end
      end
    end
  end
end
