# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Share
      # Builds the `share` confirmation payload — the witty shared-url line with a
      # CLICKABLE action-class link (target=_blank) + a copy affordance. Renders
      # Pito::Share::LinkComponent into an html: true payload (mirrors
      # Pito::MessageBuilder::Footage::Snippet).
      module Link
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param url [String] the public /share/:uuid link
        # @return [Hash] system event payload with body + html: true
        def call(url:)
          body = render_component(Pito::Share::LinkComponent.new(url:))
          html_payload(body: body)
        end
      end
    end
  end
end
