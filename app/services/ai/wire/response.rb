# frozen_string_literal: true

module Ai
  module Wire
    # The normalized shape every wire adapter returns — the orchestrator never
    # sees a provider's raw JSON. One Response per completed API call:
    #
    #   text       — assistant prose (String, may be "")
    #   tool_calls — Array<ToolCall> the model requested this turn ([] when none)
    #   usage      — Usage token counts (zeros when the provider omits them)
    #   stop_reason— normalized Symbol: :stop | :tool_use | :length | :other
    #
    # ToolCall / Usage / Error live in their own files (one constant per file,
    # zeitwerk's contract — a shared file would leave the siblings unloadable
    # until Response happened to be referenced first).
    Response = Data.define(:text, :tool_calls, :usage, :stop_reason) do
      def tool_calls? = tool_calls.any?
    end
  end
end
