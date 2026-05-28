# frozen_string_literal: true

module Pito
  module Slash
    class Dispatcher
      def self.call(input:, conversation:)
        new(input, conversation).dispatch
      end

      private_class_method :new

      def initialize(input, conversation)
        @input = input
        @conversation = conversation
      end

      def dispatch
        tokens = Pito::Lex::Lexer.call(@input)

        invocation = parse(tokens)
        return invocation if invocation.is_a?(Pito::Slash::Result::Error) # parse error

        handler_class = Pito::Slash::Registry.lookup(invocation.verb)

        if handler_class.nil?
          return Pito::Slash::Result::Error.new(
            message_key: "pito.slash.errors.unknown_verb",
            message_args: { verb: invocation.verb }
          )
        end

        handler = handler_class.new(invocation:, conversation: @conversation)
        handler.call
      end

      private

      def parse(tokens)
        Pito::Slash::Parser.call(tokens, raw: @input)
      rescue Pito::Slash::Parser::NotASlashCommand, Pito::Slash::Parser::MissingVerb => e
        Pito::Slash::Result::Error.new(
          message_key: "pito.slash.errors.parse_failed",
          message_args: { raw: @input }
        )
      end
    end
  end
end
