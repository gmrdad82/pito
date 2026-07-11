# frozen_string_literal: true

module Ai
  module Wire
    # Token accounting for Pito::Stack + per-turn budgets.
    Usage = Data.define(:input_tokens, :output_tokens) do
      def total = input_tokens.to_i + output_tokens.to_i
    end
  end
end
