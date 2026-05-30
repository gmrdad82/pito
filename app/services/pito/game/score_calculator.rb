# frozen_string_literal: true

# Vote-weighted average of the three IGDB rating triplets carried on
# `Game`. Ported from the original `Pito::ScoreBarComponent.synthesized_score`.
#
# Returns an integer 0–100 when at least one rating triplet has votes,
# or `nil` when no source contributes.
module Pito
  module Game
    class ScoreCalculator
      RATING_TRIPLETS = %i[
        igdb_rating igdb_rating_count
        aggregated_rating aggregated_rating_count
        total_rating total_rating_count
      ].freeze

      def self.call(game)
        new(game).call
      end

      def initialize(game)
        @game = game
      end

      def call
        return 0 if @game.nil?

        contributions = [
          [ @game.igdb_rating,       @game.igdb_rating_count ],
          [ @game.aggregated_rating, @game.aggregated_rating_count ],
          [ @game.total_rating,      @game.total_rating_count ]
        ].select { |rating, count| rating.present? && count.present? && count > 0 }

        return 0 if contributions.empty?

        numerator   = contributions.sum { |rating, count| rating * count }
        denominator = contributions.sum { |_, count| count }
        numerator.fdiv(denominator).round
      end
    end
  end
end
