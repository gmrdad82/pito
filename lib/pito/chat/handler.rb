# frozen_string_literal: true

require_relative "../grammar/handler_dsl"

module Pito
  module Chat
    class Handler
      extend Pito::Grammar::HandlerDsl

      attr_reader :message, :conversation

      def initialize(message:, conversation:)
        @message = message
        @conversation = conversation
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      class << self
        def verb
          @verb or raise NotImplementedError, "#{name} must define self.verb"
        end

        def verb=(value)
          @verb = value
        end

        def description_key
          @description_key or raise NotImplementedError, "#{name} must define self.description_key"
        end

        def description_key=(value)
          @description_key = value
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@verb, nil)
          subclass.instance_variable_set(:@description_key, nil)
          subclass.reset_grammar_ivars!
        end
      end
    end
  end
end
