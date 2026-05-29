# frozen_string_literal: true

module Pito
  module Chat
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
        message = parse(tokens)
        return message if message.is_a?(Pito::Chat::Result::Error)

        case message.kind
        when :new_turn
          dispatch_new_turn(message)
        when :refinement
          dispatch_refinement(message)
        when :unknown
          dispatch_unknown(message)
        end
      end

      private

      def parse(tokens)
        Pito::Chat::Parser.call(tokens, raw: @input, conversation: @conversation)
      rescue Pito::Chat::Parser::NotAChatMessage
        Pito::Chat::Result::Error.new(
          message_key: "pito.chat.errors.misrouted_slash",
          message_args: { raw: @input }
        )
      end

      def dispatch_new_turn(message)
        handler_class = Pito::Chat::Registry.lookup(message.verb)

        if handler_class.nil?
          return Pito::Chat::Result::Error.new(
            message_key: "pito.chat.errors.verb_not_implemented",
            message_args: { verb: message.verb }
          )
        end

        handler = handler_class.new(message:, conversation: @conversation)
        handler.call
      end

      def dispatch_refinement(message)
        handler = Pito::Chat::Handlers::RefineDemo.new(message:, conversation: @conversation)
        handler.call
      end

      def dispatch_unknown(message)
        handler = Pito::Chat::Handlers::Unknown.new(message:, conversation: @conversation)
        handler.call
      end
    end
  end
end
