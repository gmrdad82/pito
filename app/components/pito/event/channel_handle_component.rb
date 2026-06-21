# frozen_string_literal: true

module Pito
  module Event
    # Renders a channel handle as `@handle` in cyan.
    # Used in chatbox filter, confirmation body, and anywhere a
    # YouTube channel reference appears inline.
    class ChannelHandleComponent < ViewComponent::Base
      def initialize(handle)
        @handle = handle.to_s.presence
      end

      def render?
        @handle.present?
      end

      def call
        render(Pito::Shimmer::TokenComponent.new(text: "@#{@handle.delete_prefix("@")}"))
      end
    end
  end
end
