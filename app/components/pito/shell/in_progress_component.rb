# frozen_string_literal: true

module Pito
  module Shell
    class InProgressComponent < ViewComponent::Base
      # @param verb_key [String] i18n key for the shimmer text (e.g. "pito.shell.in_progress.building").
      def initialize(verb_key:)
        @verb_key = verb_key
      end
    end
  end
end
