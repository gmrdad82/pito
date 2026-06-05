# frozen_string_literal: true

module Pito
  module Event
    # Enhanced — 2nd+ segment in a multi-segment turn. Pito-brand left bar, no background.
    class EnhancedComponent < SystemComponent
      def accent = :pito
    end
  end
end
