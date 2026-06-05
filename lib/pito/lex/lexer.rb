# frozen_string_literal: true

# Pure function. No knowledge of slash or chat. Both Pito::Slash::Parser
# and Pito::Chat::Parser consume this.
module Pito
  module Lex
    class Lexer
      def self.call(string)
        new(string).tokenize
      end

      private_class_method :new

      def initialize(string)
        @input = string
        @pos = 0
        @tokens = []
        @space_pending = false  # set true after skipping whitespace
      end

      def tokenize
        while @pos < @input.length
          case c = current_char
          when "/"
            emit(:slash, c)
            advance
          when ":"
            emit(:colon, c)
            advance
          when "="
            emit(:equals, c)
            advance
          when ","
            emit(:comma, c)
            advance
          when "@"
            emit(:at, c)
            advance
          when "."
            emit(:dot, c)
            advance
          when '"'
            read_string
          when /\s/
            advance
            @space_pending = true
          when /[a-zA-Z]/
            read_word
          when /\d/
            read_number
          else
            emit(:unknown, c)
            advance
          end
        end

        emit(:eof, "")
        @tokens
      end

      private

      def current_char
        @input[@pos]
      end

      def advance
        @pos += 1
      end

      def peek
        @input[@pos + 1]
      end

      def emit(type, value, position = nil)
        # EOF is a sentinel — preceded_by_space is always false (it's never slurped).
        preceded = (type != :eof) && @space_pending
        @space_pending = false
        @tokens << Pito::Lex::Token.new(
          type:,
          value:,
          position:          position || @pos,
          preceded_by_space: preceded
        )
      end

      def read_word
        start_pos = @pos
        @pos += 1
        @pos += 1 while @pos < @input.length && current_char.match?(/[a-zA-Z0-9_-]/)

        # URL detection: word immediately followed by "://" (e.g. http://, https://).
        # Consume everything up to the next whitespace as one token so that
        # "localhost:3027" inside a URL isn't mistaken for a kwarg key.
        if @input[@pos, 3] == "://"
          @pos += 3
          @pos += 1 while @pos < @input.length && !current_char.match?(/\s/)
        end

        emit(:word, @input[start_pos...@pos], start_pos)
      end

      def read_number
        start_pos = @pos
        @pos += 1
        @pos += 1 while @pos < @input.length && current_char.match?(/\d/)
        emit(:number, @input[start_pos...@pos], start_pos)
      end

      def read_string
        start_pos = @pos
        @pos += 1 # skip opening "
        value = +""
        while @pos < @input.length
          if current_char == '"'
            @pos += 1 # skip closing "
            break
          elsif current_char == "\\" && peek == '"'
            value << '"'
            @pos += 2
          else
            value << current_char
            @pos += 1
          end
        end
        emit(:string, value, start_pos)
      end
    end
  end
end
