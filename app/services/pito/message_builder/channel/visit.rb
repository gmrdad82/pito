# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for a channel visit message.
      #
      # Renders Pito::Channel::VisitComponent which includes a shimmer span and
      # a hidden anchor that is auto-clicked by the pito--auto-visit Stimulus
      # controller to open the channel's YouTube page in a new tab.
      module Visit
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel [::Channel]
        # @return [Hash] string-keyed HTML payload.
        def call(channel)
          html = render_component(Pito::Channel::VisitComponent.new(channel:))
          html_payload(body: html)
        end
      end
    end
  end
end
