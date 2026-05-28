# frozen_string_literal: true

module Pito
  module Stream
    class EventPayload
      ValidationError = Class.new(StandardError)

      def self.validate!(kind:, payload:) # rubocop:disable Lint/UnusedMethodArgument
        unless ::Event::KINDS.include?(kind.to_s)
          raise ValidationError,
            "invalid event kind: #{kind.inspect} (must be one of #{::Event::KINDS.inspect})"
        end

        true
      end
    end
  end
end
