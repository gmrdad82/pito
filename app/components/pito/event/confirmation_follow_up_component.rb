# frozen_string_literal: true

module Pito
  module Event
    # ConfirmationFollowUp — a Confirmation segment after #handle confirm/cancel.
    # Same orange border as Confirmation, adds --bg-elevated background.
    class ConfirmationFollowUpComponent < ConfirmationComponent
      def background = "var(--bg-elevated)"
    end
  end
end
