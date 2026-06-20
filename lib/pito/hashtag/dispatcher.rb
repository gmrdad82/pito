# frozen_string_literal: true

module Pito
  module Hashtag
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
        tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(@input))
        message = parse(tokens)
        return message if message.is_a?(Pito::Hashtag::Result::Error)

        handler_class = Pito::Hashtag::Registry.lookup(message.handle)

        # Fallback to Reply — hashtags are a reply mechanism.
        if handler_class.nil? &&
           Pito::Hashtag.const_defined?(:Handlers) &&
           Pito::Hashtag::Handlers.const_defined?(:Reply)
          handler_class = Pito::Hashtag::Handlers::Reply
        end

        if handler_class.nil?
          return Pito::Hashtag::Result::Error.new(
            message_key: "pito.hashtag.errors.unknown_handle",
            message_args: { handle: message.handle }
          )
        end

        handler = handler_class.new(message:, conversation: @conversation)
        handler.call
      end

      private

      def parse(tokens)
        Pito::Hashtag::Parser.call(tokens, raw: @input)
      rescue Pito::Hashtag::Parser::NotAHashtag, Pito::Hashtag::Parser::InvalidHandle => e
        Pito::Hashtag::Result::Error.new(
          message_key: "pito.hashtag.errors.parse_failed",
          message_args: { raw: @input }
        )
      end
    end
  end
end
