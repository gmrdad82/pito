# frozen_string_literal: true

module Pito
  module Lex
    Token = Data.define(:type, :value, :position, :preceded_by_space) do
      # type              — Symbol token type (:slash, :word, :number, etc.)
      # value             — String literal matched at the source position
      # position          — Integer column offset in the original input
      # preceded_by_space — Boolean; true when at least one whitespace character
      #                     appeared immediately before this token in the source.
      #                     Consumers that don't need whitespace-boundary info
      #                     can safely ignore this field.
      def initialize(type:, value:, position:, preceded_by_space: false)
        super
      end
    end
  end
end
