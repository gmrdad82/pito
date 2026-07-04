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
      # All user-facing strings come from Pito::Copy
      # (`pito.copy.list.channels_help.*`).
      module ListHelp
        class << self
          # @return [Hash] system payload ({ "html" => true, "body" => <pre block> })
          def call
            groups = [
              [ c("options_title"), option_rows ]
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

          def c(key) = Pito::Copy.render("pito.copy.list.channels_help.#{key}")
        end
      end
    end
  end
end
