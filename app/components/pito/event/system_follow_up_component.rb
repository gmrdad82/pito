# frozen_string_literal: true

module Pito
  module Event
    # SystemFollowUp — a System segment promoted by a #handle reply.
    # Same surface border as System, adds --bg-elevated background.
    class SystemFollowUpComponent < SystemComponent
      def background = "var(--bg-elevated)"
    end
  end
end
