# frozen_string_literal: true

module Pito
  module Slash
    class Dispatcher
      def self.call(input:, conversation:, authenticated: true)
        new(input, conversation, authenticated).dispatch
      end

      private_class_method :new

      def initialize(input, conversation, authenticated)
        @input         = input
        @conversation  = conversation
        @authenticated = authenticated
      end

      def dispatch
        tokens = Pito::Lex::Lexer.call(@input)

        invocation = parse(tokens)
        return invocation if invocation.is_a?(Pito::Slash::Result::Error)

        # P56: universal --help / -h flag — intercept before the handler executes.
        # This fires for every command, including ones without a handler class
        # (login, logout, connect, new, resume), so no command can silently eat
        # the flag and produce side effects.
        if help_requested?(invocation)
          return Pito::Slash::HelpRenderer.call(invocation:, authenticated: @authenticated)
        end

        handler_class = Pito::Slash::Registry.lookup(invocation.verb)

        if handler_class.nil?
          return Pito::Slash::Result::Error.new(
            message_key: "pito.slash.errors.unknown_verb",
            message_args: { verb: invocation.verb }
          )
        end

        handler = handler_class.new(
          invocation:,
          conversation:  @conversation,
          authenticated: @authenticated
        )
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

      def help_requested?(invocation)
        invocation.raw.match?(/\s--help\b|\s-h\b/)
      end
    end
  end
end
