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

    # Raised when Voyage AI returns nil for an embedding request.
    class VoyageEmbeddingNil < Base
      def initialize(resource_type:, resource_id:)
        super(resource_type: resource_type, resource_id: resource_id)
      end

      private

      def build_message
        "Voyage embedding returned nil for " \
          "#{@attrs[:resource_type]} ##{@attrs[:resource_id]}"
      end
    end

    # Raised when an external HTTP fetch returns a non-success status.
    class ExternalFetchFailed < Base
      def initialize(source:, http_code:, detail: nil)
        super(source: source, http_code: http_code, detail: detail)
      end

      private

      def build_message
        msg = "#{@attrs[:source]} returned #{@attrs[:http_code]}"
        msg += " (#{@attrs[:detail]})" if @attrs[:detail]
        msg
      end
    end

    # Raised when a required credential or config value is missing at boot.
    class MissingConfiguration < Base
      def initialize(key:, hint: nil)
        super(key: key, hint: hint)
      end

      private

      def build_message
        msg = "missing configuration: #{@attrs[:key]}"
        msg += " — #{@attrs[:hint]}" if @attrs[:hint]
        msg
      end
    end
  end
end
