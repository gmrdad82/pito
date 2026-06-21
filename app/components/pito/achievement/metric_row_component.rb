# frozen_string_literal: true

module Pito
  module Achievement
    # Renders one metric's full progress row inside a shinies detail card.
    #
    # Structure (top to bottom):
    #   1. Full-width TrackComponent — label is the metric word, current_value
    #      sourced from the entity's AchievementMetric row (0 when none exists).
    #   2. Obtained badges — all Achievement rows for this (entity, metric),
    #      ordered by unlocked_at ascending so the earliest drop appears first.
    #
    # A metric with no obtained shinies is hidden entirely (no track, no label) —
    # an empty progress row is noise, not signal.
    class MetricRowComponent < ViewComponent::Base
      def initialize(entity:, metric:)
        @entity = entity
        @metric = metric.to_s
      end

      # Hide the whole row when this metric has no obtained shinies yet.
      def render?
        obtained_achievements.any?
      end

      # Full word label for the metric, title-cased (via Pito::Achievements::Label.for).
      def label
        Pito::Achievements::Label.for(@metric)
      end

      # Lifetime value for this metric on the entity.  Falls back to 0 when no
      # AchievementMetric row exists yet (track renders all-upcoming).
      def current_value
        @entity.achievement_metrics.find_by(metric: @metric)&.value.to_i
      end

      # All obtained Achievement rows for this entity + metric, earliest first.
      def obtained_achievements
        @entity.achievements.where(metric: @metric).order(:unlocked_at)
      end
    end
  end
end
