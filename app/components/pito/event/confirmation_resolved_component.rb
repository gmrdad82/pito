# frozen_string_literal: true

module Pito
  module Event
    # Hairline separator + outcome text shown after a confirmation resolves.
    class ConfirmationResolvedComponent < ViewComponent::Base
      def initialize(outcome_text:)
        @outcome_text = outcome_text
      end
    end
  end
end
