# frozen_string_literal: true

module Ai
  # Executes ONE read tool call mid-loop and hands back markdown for the
  # tool_result message. NEVER raises into the orchestrator's loop and NEVER
  # persists anything — Pito::Mcp::Executor already guarantees no persistence
  # (dispatch-only, no jobs); this class adds a raise-safe boundary plus an
  # unknown-tool short-circuit on top of it.
  #
  # The terminal tool names ("pito_render_command" / "pito_respond") are
  # intercepted by the orchestrator before a call ever reaches here — they are
  # not entries in the MCP Registry, so they fall into the unknown-tool branch
  # below like any other bad name.
  #
  #   Ai::ToolExecutor.call(name: "pito_show", arguments: { "noun" => "vids" })
  #   # => { content: "<markdown>", error: false }
  module ToolExecutor
    module_function

    # @param name [String] the MCP tool name
    # @param arguments [Hash, nil] the tool-call arguments
    # @return [Hash] { content: String, error: Boolean }
    WEB_TOOLS = {
      "web_search" => ->(args) { Ai::Web::Search.call(query: args["query"]) },
      "web_fetch"  => ->(args) { Ai::Web::Fetch.call(url: args["url"]) }
    }.freeze

    def call(name:, arguments:)
      if (web = WEB_TOOLS[name.to_s])
        result = web.call(arguments || {})
        error  = result.key?(:error)
        return { content: JSON.pretty_generate(result), error: error }
      end
      return unknown_tool(name) if Pito::Mcp::Registry.tool(name).nil?

      result = Pito::Mcp::Executor.call(tool: name, arguments: arguments || {})
      { content: result.text, error: result.error? }
    rescue StandardError => e
      Rails.logger.warn("[Ai::ToolExecutor] #{name}: #{e.class}: #{e.message}")
      { content: "Tool #{name} failed: #{e.message}", error: true }
    end

    def unknown_tool(name)
      names = Pito::Mcp::Registry.tool_names.join(", ")
      { content: "Unknown tool #{name}. Available: #{names}.", error: true }
    end
  end
end
