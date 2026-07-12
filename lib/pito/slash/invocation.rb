# frozen_string_literal: true

module Pito
  module Slash
    Invocation = Data.define(:tool, :args, :kwargs, :raw) do
      # tool   — Symbol, the command tool (:help, :publish, etc.)
      # args   — Array of positional arguments (strings / numbers)
      # kwargs — Hash of keyword arguments (symbol keys)
      # raw    — String, the original input
    end
  end
end
