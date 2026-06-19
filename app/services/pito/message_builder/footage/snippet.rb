# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Footage
      # Builds the payload Hash for the `footage snippet` system event.
      #
      # Renders Pito::Footage::SnippetComponent into an html: true payload. The
      # component embeds a leading `data-pito-ts-slot` span so the message's
      # "HH:MM ·" timestamp lands inline on the first line, like other system
      # messages.
      #
      # == Usage
      #
      #   payload = Pito::MessageBuilder::Footage::Snippet.call
      #   # => { "body" => "<div class=\"pito-footage-snippet\">…</div>", "html" => true }
      module Snippet
        extend Pito::MessageBuilder::Helpers
        module_function

        # @return [Hash] system event payload with body and html: true.
        def call
          body = render_component(Pito::Footage::SnippetComponent.new)
          html_payload(body: body)
        end
      end
    end
  end
end
