# frozen_string_literal: true

module Pito
  module Chat
    class Dispatcher
      def self.call(input:, conversation:, channel: nil, follow_up: nil)
        new(input, conversation, channel, follow_up).dispatch
      end

      private_class_method :new

      def initialize(input, conversation, channel = nil, follow_up = nil)
        @input = input
        @conversation = conversation
        @channel = channel
        @follow_up = follow_up
      end

      def dispatch
        tokens = Pito::Lex::Lexer.call(@input)
        message = parse(tokens)
        return message if message.is_a?(Pito::Chat::Result::Error)

        case message.kind
        when :new_turn
          dispatch_new_turn(message)
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

        if message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/)
          payload = Pito::MessageBuilder::CommandHelp.call(verb: message.verb)
          return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ]) if payload
        end

        handler = handler_class.new(message:, conversation: @conversation, channel: @channel, follow_up: @follow_up)
        handler.call
      end

      def dispatch_unknown(message)
        handler = Pito::Chat::Handlers::Unknown.new(message:, conversation: @conversation, channel: @channel, follow_up: @follow_up)
        handler.call
      end
    end
  end
end
