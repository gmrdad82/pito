# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builder for the `list videos --help` system message.
      #
      # Mirrors Game::ListHelp but for videos: renders a `Usage:` line, an
      # `Options:` group, and a `Columns:` group derived from
      # Video::ListColumns::COLUMNS. All user-facing strings come from Pito::Copy
      # (`pito.copy.list.videos_help.*`).
      module ListHelp
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
              [ c("opt_with"),   c("opt_with_desc") ],
              [ c("opt_sorted"), c("opt_sorted_desc") ],
              [ c("opt_help"),   c("opt_help_desc") ]
            ]
          end

          # [token, description] pairs for the Columns group — tokens are the
          # real parser aliases, descriptions come from copy keyed by canonical.
          def column_rows
            # PUBLIC_COLUMNS only — internal columns (e.g. the slate's :scheduled)
            # are not user-addable, so they never appear in the help.
            ListColumns::PUBLIC_COLUMNS.map do |canonical, cfg|
              [ cfg[:aliases].join(", "), c("col_#{canonical}_desc") ]
            end
          end

          def c(key) = Pito::Copy.render("pito.copy.list.videos_help.#{key}")
        end
      end
    end
  end
end
