# frozen_string_literal: true

# Pure function. Picks ONE Achievement per metric — the highest threshold
# reached in each lane (the last unlocked) — ordered most-recently-advanced
# first. The shared "Shinies" row logic of the channel / video / game detail
# cards (was copy-pasted in all three components before this).
#
#   Pito::Achievements::TopShiniesPerMetric.call(channel.achievements)
#   # => [Achievement, …] one per metric, newest lane first
module Pito
  module Achievements
    module TopShiniesPerMetric
      module_function

      # @param achievements [Enumerable<Achievement>] an achievable's achievements
      # @return [Array<Achievement>]
      def call(achievements)
        achievements
          .group_by(&:metric)
          .values
          .map { |lane| lane.max_by(&:threshold) }
          .sort_by { |a| -a.unlocked_at.to_i }
      end
    end
  end
end
