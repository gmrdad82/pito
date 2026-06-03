# frozen_string_literal: true

module Pito
  module Event
    # Renders a channel title in bold.
    # Used in connection messages, confirmation segments, and anywhere
    # a channel name needs prominence.
    class ChannelTitleComponent < ViewComponent::Base
      def initialize(title)
        @title = title.to_s.presence
      end

      def render?
        @title.present?
      end

      def call
        tag.span("\"#{@title}\"", class: "font-bold")
      end
    end
  end
end
