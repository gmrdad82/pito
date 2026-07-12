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
        tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(@input))

        invocation = parse(tokens)
        return invocation if invocation.is_a?(Pito::Slash::Result::Error)

        # Universal --help / -h flag — intercept before the handler executes.
        # This fires for every command, including ones without a handler class
        # (login, logout, connect, new, resume), so no command can silently eat
        # the flag and produce side effects.
        if help_requested?(invocation)
          return Pito::Slash::HelpBuilder.call(invocation:)
        end

        handler_class = Pito::Slash::Registry.lookup(invocation.tool)

        if handler_class.nil?
          return Pito::Slash::Result::Error.new(
            message_key: "pito.slash.errors.unknown_tool",
            message_args: { tool: invocation.tool }
          )
        end

        # Generic positional-arity guard — rejects invocations that pass more
        # positional args than the grammar spec can absorb.
        #
        # Opt-out: handlers with `self.validates_own_arity = true` are skipped
        # here because they validate their own argument count internally
        # (e.g. Games — subcommand keyword with optional title).
        #
        # Capacity rules:
        #   - kv slots do NOT count — they consume key=value kwargs, not positional args.
        #   - If any positional slot is repeatable? or kind :free → capacity = unbounded.
        #   - Otherwise capacity = number of positional slots.
        #
        # Commands with no grammar spec are silently skipped (not validated).
        unless handler_class.validates_own_arity
          spec = Pito::Grammar::Registry.specs_for_alias(namespace: :slash, token: invocation.tool)
          if spec
            positional_slots = spec.slots.reject { |s| s.kind == :kv || s.kind == :connective }
            unbounded = positional_slots.any? { |s| s.repeatable? || s.kind == :free }

            unless unbounded
              capacity = positional_slots.size
              if invocation.args.size > capacity
                return Pito::Slash::Result::Error.new(
                  message_key:  "pito.slash.errors.too_many_args",
                  message_args: { tool: invocation.tool }
                )
              end
            end
          end
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
      rescue Pito::Slash::Parser::NotASlashCommand, Pito::Slash::Parser::MissingTool => e
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
