# frozen_string_literal: true

# Central registry for structured error types across Pito systems.
#
# Every error class defined here carries a `#to_h` payload suitable for
# event payloads, logs, and the error result pipeline (`Result::Error`).
module Pito
  module Error
    class Base < StandardError
      def initialize(**attrs)
        @attrs = attrs
        super(build_message)
      end

      def to_h
        @attrs
      end

      private

      def build_message
        raise NotImplementedError
      end
    end

    # Raised when an auto-computed score would drift beyond the
    # configured threshold (Game::SCORE_DRIFT_THRESHOLD).
    class ScoreDrift < Base
      def initialize(game:, old_score:, new_score:)
        super(game: game, old_score: old_score, new_score: new_score)
      end

      private

      def build_message
        "Score drift: #{@attrs[:old_score]} → #{@attrs[:new_score]} (game #{@attrs[:game].id})"
      end
    end
  end
end
