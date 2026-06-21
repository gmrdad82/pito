# frozen_string_literal: true

module Pito
  module Achievement
    # Renders the full shinies detail view for a single entity.
    #
    # Structure:
    #   - Optional intro line (with timestamp slot for the event chrome).
    #   - One MetricRowComponent per metric in Evaluate.metrics_for(entity),
    #     always rendered — even when a metric has no obtained shinies, the track
    #     still shows the upcoming milestones.
    class ShiniesComponent < ViewComponent::Base
      def initialize(entity:, intro: nil)
        @entity = entity
        @intro  = intro
      end

      def metrics
        Pito::Achievements::Evaluate.metrics_for(@entity)
      end
    end
  end
end
