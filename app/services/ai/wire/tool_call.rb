# frozen_string_literal: true

module Ai
  module Wire
    # One requested tool invocation. `arguments` is the PARSED Hash (string
    # keys); adapters that receive malformed argument JSON substitute {} and
    # let the orchestrator surface the tool-level error back to the model.
    ToolCall = Data.define(:id, :name, :arguments)
  end
end
