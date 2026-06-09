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
        GAP = 3 # spaces between the token column and the description column

        class << self
          # @return [Hash] system payload ({ html: true, body: <pre block> })
          def call
            { "html" => true, "body" => render_block }
          end

          private

          def render_block
            width = (option_rows + column_rows).map { |tok, _| tok.length }.max + GAP

            lines = []
            lines << header(c("usage_title"))
            lines << "  #{dim(esc(c('usage')))}"
            lines << ""
            lines << header(c("options_title"))
            option_rows.each { |tok, desc| lines << row(tok, desc, width) }
            lines << ""
            lines << header(c("columns_title"))
            column_rows.each { |tok, desc| lines << row(tok, desc, width) }

            %(<div class="pito-help-block">#{lines.join("\n")}</div>)
          end

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

          # One aligned `  <token>   <description>` line. Padding is computed on
          # the raw (pre-escape) token length so the monospace columns line up.
          def row(token, desc, width)
            pad = " " * (width - token.length)
            "  #{cyan(esc(token))}#{pad}#{dim(esc(desc))}"
          end

          def header(text) = %(<span class="text-yellow font-bold">#{esc(text)}</span>)
          def cyan(html)   = %(<span class="text-cyan">#{html}</span>)
          def dim(html)    = %(<span class="text-fg-dim">#{html}</span>)
          def esc(text)    = ERB::Util.html_escape(text)
          def c(key)       = Pito::Copy.render("pito.copy.list.games_help.#{key}")
        end
      end
    end
  end
end
