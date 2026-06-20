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
      # `list channels` carries no `with <columns>` or `sorted by` options (it
      # shows a fixed card view), so the Options group lists only --help.
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
              [ c("opt_help"), c("opt_help_desc") ]
            ]
          end

          def c(key) = Pito::Copy.render("pito.copy.list.channels_help.#{key}")
        end
      end
    end
  end
end
