# frozen_string_literal: true

module Pito
  module Slash
    class Parser
      NotASlashCommand = Class.new(StandardError)
      MissingVerb       = Class.new(StandardError)

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
        raise NotASlashCommand, "input must start with /" unless current_token&.type == :slash
        advance

        raise MissingVerb, "expected a verb after /" unless current_token&.type == :word
        verb = current_token.value.to_sym
        advance

        args = []
        kwargs = {}

        until eof?
          if kwarg_key?
            key = current_token.value.to_sym
            advance # skip the key word
            advance # skip colon/equals
            value = read_value
            kwargs[key] = value
          else
            args << read_value
          end
        end

        Invocation.new(verb:, args:, kwargs:, raw: @raw)
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

      # A word followed by :colon or :equals signals a keyword argument
      def kwarg_key?
        return false unless current_token&.type == :word

        next_tok = @tokens[@pos + 1]
        next_tok && (next_tok.type == :colon || next_tok.type == :equals)
      end

      def read_value
        tok = current_token

        # Quoted strings are already complete — return immediately.
        if tok.type == :string
          advance
          return tok.value
        end

        # Slurp consecutive tokens until we hit a kwarg boundary
        # (word followed by colon or equals) or EOF.
        parts = []
        loop do
          break if eof?
          break if kwarg_boundary?

          parts << current_token.value.to_s
          advance
        end

        joined = parts.join

        # Preserve numeric return type when the result is a pure number.
        return joined.to_i if joined.match?(/\A\d+\z/)
        return joined.to_f if joined.match?(/\A\d+\.\d+\z/)

        joined
      end

      # True when the current token marks the start of a new kwarg key
      # (word followed by :colon or :equals).
      def kwarg_boundary?
        current_token.type == :word &&
          @tokens[@pos + 1]&.type.in?([ :colon, :equals ])
      end
    end
  end
end
