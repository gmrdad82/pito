# frozen_string_literal: true

module Pito
  module Analytics
    module Support
      # The metric name/label piece of an analytics slot (e.g. "Views", "Likes").
      # Extracted so a Slot only composes [visualizer] + [MetricName] + [scalar]
      # rather than inlining the label markup.
      class MetricName < ViewComponent::Base
        # @param name [String] the metric's display name (already localized).
        def initialize(name:)
          @name = name
        end

        attr_reader :name
      end
    end
  end
end
