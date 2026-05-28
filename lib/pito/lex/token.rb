# frozen_string_literal: true

module Pito
  module Lex
    Token = Data.define(:type, :value, :position) do
      # type   — Symbol token type (:slash, :word, :number, etc.)
      # value  — String literal matched at the source position
      # position — Integer column offset in the original input
    end
  end
end
