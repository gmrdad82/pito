# frozen_string_literal: true

require_relative "../grammar/handler_dsl"

module Pito
  module Slash
    class Handler
      extend Pito::Grammar::HandlerDsl

      attr_reader :invocation, :conversation, :authenticated

      def initialize(invocation:, conversation:, authenticated: true)
        @invocation    = invocation
        @conversation  = conversation
        @authenticated = authenticated
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # Returns true when the raw input contains the --help flag.
      # Handlers call `return show_help if help?` at the top of #call.
      def help?
        invocation.raw.match?(/--help\b/)
      end

      # Default --help response. Override in each handler to provide
      # command-specific usage. The boilerplate is: (1) add
      # `return show_help if help?` at the top of #call, and (2) override
      # this method with actual content.
      def show_help
        Pito::Slash::Result::Ok.new(events: [
          {
            kind:    "system",
            payload: { text: "No --help defined for /#{self.class.verb}. Try /help for the command list." }
          }
        ])
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
