# frozen_string_literal: true

module Pito
  module Hashtag
    class Parser
      NotAHashtag = Class.new(StandardError)
      InvalidHandle = Class.new(StandardError)

      def self.call(tokens, raw:)
        new(tokens, raw).parse
      end

      private_class_method :new

      def initialize(tokens, raw)
        @tokens = tokens
        @raw = raw
        @pos = 0
      end

      def parse
        raise NotAHashtag, "input must start with #" unless @raw.start_with?("#")

        # Skip the # token (emitted as :unknown) and any leading non-word tokens.
        advance while current_token && current_token.type != :word && current_token.type != :eof

        raise InvalidHandle, "expected handle after #" unless current_token&.type == :word

        handle_token = current_token.value.to_s
        handle_word = handle_token.split("-", 2).first.to_sym
        advance

        body_tokens = tokens_until_eof

        Message.new(handle: handle_word, body_tokens:, raw: @raw)
      end

      private

      def current_token
        @tokens[@pos]
      end

      def advance
        @pos += 1
      end

      def eof?
        current_token&.type == :eof
      end

      def tokens_until_eof
        result = []
        until eof?
          result << current_token
          advance
        end
        result
      end
    end
  end
end
