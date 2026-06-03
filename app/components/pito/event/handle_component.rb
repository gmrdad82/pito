# frozen_string_literal: true

module Pito
  module Event
    # Renders a confirmation / segment handle as `#handle` in purple.
    # Used inside MetaLineComponent and anywhere a handle token appears inline.
    class HandleComponent < ViewComponent::Base
      def initialize(handle)
        @handle = handle.to_s.presence
      end

      def render?
        @handle.present?
      end

      def call
        tag.span("##{@handle}", class: "text-purple")
      end
    end
  end
end
