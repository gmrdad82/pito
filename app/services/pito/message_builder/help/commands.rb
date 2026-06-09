# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Help
      # Builder for the chat `help` verb — a simple, always-visible system message
      # listing available chat commands grouped by category.
      #
      # == Output shape
      #
      # Returns a Hash with:
      #   body  — raw HTML fragment (html: true); a yellow bold "GAMES" heading
      #           rendered via Tailwind utility classes.
      #   html  — true (so the body renders instantly without typewriter)
      #   table_rows — one kv row: { key: "list games", value: "use --help for more info" }
      #
      # The `sections` key is intentionally absent so the content is always
      # visible (sections are hidden behind the ctrl+| expand toggle).
      module Commands
        class << self
          # @return [Hash] system payload with html body + table_rows
          def call
            {
              "body"       => group_title_html,
              "html"       => true,
              "table_rows" => [
                {
                  "key"   => Pito::Copy.render("pito.copy.help.list_games_label"),
                  "value" => Pito::Copy.render("pito.copy.help.list_games_hint")
                }
              ]
            }
          end

          private

          def group_title_html
            title = ERB::Util.html_escape(Pito::Copy.render("pito.copy.help.games_group_title"))
            %(<div class="text-yellow font-bold">#{title}</div>)
          end
        end
      end
    end
  end
end
