# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builder for the `list channels --help` system message.
      #
      # Renders the `Usage: list channels` header via ManPage (for consistent
      # yellow bold styling), then appends one random witty one-liner from the
      # `pito.copy.list.channels_help` array.
      module ListHelp
        module_function

        # @return [Hash] system payload ({ "html" => true, "body" => <pre block> })
        def call
          header_body = Pito::MessageBuilder::ManPage.render(
            usage: "list channels",
            groups: []
          )
          witty = Pito::Copy.render("pito.copy.list.channels_help")
          body = "#{header_body}<p class=\"text-fg-dim\">#{ERB::Util.html_escape(witty)}</p>"
          { "html" => true, "body" => body.html_safe }
        end
      end
    end
  end
end
