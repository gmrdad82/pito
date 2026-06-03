# frozen_string_literal: true

module Pito
  module Event
    # SystemFollowUp — a System segment promoted by a #handle reply.
    # Same surface border as System, adds --bg-elevated background.
    # Inherits from EnhancedComponent so its template (which delegates to
    # ExpandableBodyComponent + MetaLineComponent) is reused. ViewComponent
    # falls back to the parent template when a child template is missing.
    class SystemFollowUpComponent < EnhancedComponent
      def accent = :surface
      def background = "var(--bg-elevated)"
    end
  end
end
