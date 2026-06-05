# frozen_string_literal: true

module Pito
  module Event
    # EnhancedFollowUp — an Enhanced segment promoted by a #handle reply.
    # Same pito border as Enhanced, adds --bg-elevated background.
    class EnhancedFollowUpComponent < EnhancedComponent
      def background = "var(--bg-elevated)"
    end
  end
end
