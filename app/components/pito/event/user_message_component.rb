# frozen_string_literal: true

module Pito
  module Event
    class UserMessageComponent < ViewComponent::Base
      # @param body [String] the user's message text.
      def initialize(body:)
        @body = body
      end
    end
  end
end
