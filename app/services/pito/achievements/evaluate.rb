# frozen_string_literal: true

module Pito
  module Achievements
    # Idempotent, unlock-once evaluator for a single (achievable, metric, value) triple.
    #
    # For every threshold in the (scope, metric) ladder that is ≤ value,
    # ensures exactly one Achievement row exists. Already-unlocked thresholds
    # are never touched — the underlying INSERT uses ON CONFLICT DO NOTHING so
    # existing rows (and their original +unlocked_at+) are preserved even under
    # concurrent calls.
    #
    # Returns only the newly-created Achievement records as an array (empty
    # when all relevant thresholds were already unlocked).
    #
    # Usage:
    #   Pito::Achievements::Evaluate.call(achievable: video, metric: "views", value: 1_500)
    #   # => [#<Achievement threshold=1>, #<Achievement threshold=2>, ...]
    module Evaluate
      # Valid metrics per achievable type.
      # Only Channel has +subs+ (total subscriber count).
      # Only Video / Game have +subs_gained+ (subscribers gained in a period).
      MATRIX = {
        "Channel" => %w[subs views watched_hours likes comments].freeze,
        "Video"   => %w[subs_gained views watched_hours likes comments].freeze,
        "Game"    => %w[subs_gained views watched_hours likes comments].freeze
      }.freeze

      module_function

      # Returns the valid metric list for +achievable+'s type.
      #
      # @param achievable [Channel, Video, Game]
      # @return [Array<String>]
      def metrics_for(achievable)
        MATRIX.fetch(achievable.class.polymorphic_name, [])
      end

      # Evaluate +value+ against the milestone series and unlock every
      # threshold that has not yet been recorded for +(achievable, metric)+.
      #
      # @param achievable [Channel, Video, Game]
      # @param metric     [String]  must be in {metrics_for}(achievable)
      # @param value      [Integer] current counter value
      # @return [Array<Achievement>] newly-unlocked records (empty if none new)
      # @raise [ArgumentError] when +metric+ is not valid for +achievable+'s type
      def call(achievable:, metric:, value:)
        metric = metric.to_s
        valid  = metrics_for(achievable)

        unless valid.include?(metric)
          raise ArgumentError,
                "metric #{metric.inspect} is not valid for #{achievable.class.name} " \
                "(expected one of #{valid.inspect})"
        end

        scope      = achievable.class.polymorphic_name
        thresholds = Pito::Achievement::Tier.series_for(scope:, metric:).select { |t| t <= value }
        return [] if thresholds.empty?

        now  = Time.current
        type = scope
        id   = achievable.id

        rows = thresholds.map do |threshold|
          {
            achievable_type: type,
            achievable_id:   id,
            metric:          metric,
            threshold:       threshold,
            unlocked_at:     now,
            created_at:      now,
            updated_at:      now
          }
        end

        # INSERT … ON CONFLICT (achievable_type, achievable_id, metric, threshold)
        # DO NOTHING RETURNING id — atomically skips existing rows and returns
        # only the IDs of rows that were actually inserted this call.
        # Use ::Achievement (top-level model) — inside Pito::Achievements,
        # bare `Achievement` resolves to Pito::Achievement (the component module).
        result = ::Achievement.insert_all(
          rows,
          unique_by: %i[achievable_type achievable_id metric threshold],
          returning: %w[id]
        )

        new_ids = result.rows.flatten
        return [] if new_ids.empty?

        ::Achievement.where(id: new_ids).to_a
      end
    end
  end
end
