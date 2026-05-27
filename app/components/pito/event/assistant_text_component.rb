# frozen_string_literal: true

module Pito
  module Event
    class AssistantTextComponent < ViewComponent::Base
      # @param body [String, nil] optional plain text body.
      #   If nil, render block content instead (rich body slot).
      def initialize(body: nil)
        @body = body
      end
    end
  end
end
