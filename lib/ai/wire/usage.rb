# frozen_string_literal: true

module Ai
  module Wire
    # Token accounting for Pito::Stack + per-turn budgets.
    # cost: the PROVIDER-REPORTED price of the call in USD (OpenCode Zen and
    # OpenRouter include it in responses) — nil when the provider doesn't
    # report one. Reported cost always beats computed cost downstream.
    Usage = Data.define(:input_tokens, :output_tokens, :cost) do
      def initialize(input_tokens:, output_tokens:, cost: nil)
        super
      end

      def total = input_tokens.to_i + output_tokens.to_i
    end
  end
end
