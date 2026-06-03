# frozen_string_literal: true

module Pito
  module Hashtag
    class Handler
      attr_reader :message, :conversation

      def initialize(message:, conversation:)
        @message = message
        @conversation = conversation
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      class << self
        def handle
          @handle or raise NotImplementedError, "#{name} must define self.handle"
        end

        def handle=(value)
          @handle = value
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@handle, nil)
        end
      end
    end
  end
end
