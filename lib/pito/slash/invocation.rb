# frozen_string_literal: true

module Pito
  module Slash
    Invocation = Data.define(:verb, :args, :kwargs, :raw) do
      # verb   — Symbol, the command verb (:help, :publish, etc.)
      # args   — Array of positional arguments (strings / numbers)
      # kwargs — Hash of keyword arguments (symbol keys)
      # raw    — String, the original input
    end
  end
end
