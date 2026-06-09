# frozen_string_literal: true

module Pito
  module Lex
    # Pure function — no knowledge of slash, hashtag, or chat grammar.
    # Both Pito::Slash::Parser and the normalizer pipeline consume this.
    #
    # CONTRACT
    #   self.call(string) -> Array<Pito::Lex::Token>
    #   Always ends with exactly one :eof sentinel token.
    #
    # TOKEN TYPES EMITTED
    #   :slash    — the "/" character
    #   :colon    — the ":" character
    #   :equals   — the "=" character
    #   :comma    — the "," character
    #   :at       — the "@" character (bare; handle fusion is done by downstream consumers)
    #   :dot      — the "." character
    #   :word     — a sequence of [a-zA-Z][a-zA-Z0-9_-']* (an apostrophe may also
    #               LEAD a word when a letter follows, e.g. "'n" in "Ghosts 'n
    #               Goblins"; "don't" / "Ghosts'" keep their apostrophe too)
    #               URL-slurp rule: when immediately followed by "://" the word is
    #               extended to consume all characters up to the next whitespace,
    #               keeping "http://host:port/path" as a single :word token so that
    #               the port colon isn't mistaken for a kwarg separator.
    #   :number   — a sequence of [0-9]+
    #   :string   — a double-quoted literal with \" escape support;
    #               the value field holds the unescaped content (quotes stripped)
    #   :unknown  — any character not matched by the rules above
    #   :eof      — sentinel; value is always ""; never has preceded_by_space=true
    #
    # WHITESPACE CONTRACT
    #   Whitespace characters are consumed and DROPPED — they never appear as tokens.
    #   Instead, the next non-whitespace token carries preceded_by_space: true.
    #   Downstream parsers use this flag to detect argument boundaries without
    #   needing to insert explicit separator tokens.
    #   The :eof sentinel always has preceded_by_space: false (it is never a real token).
    #
    # @!attribute [r] @space_pending
    #   Set true after consuming whitespace; cleared (and transferred to next token) on emit.
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
          when "'"
            # Apostrophe-led word like "'n" / "'em" / "'tis" — only when a letter
            # follows, so a lone/closing apostrophe still falls through to :unknown.
            if peek&.match?(/[a-zA-Z]/)
              read_word
            else
              emit(:unknown, c)
              advance
            end
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
        @pos += 1 while @pos < @input.length && current_char.match?(/[a-zA-Z0-9_\-']/)

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
