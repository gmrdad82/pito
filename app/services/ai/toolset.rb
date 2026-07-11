# frozen_string_literal: true

module Ai
  # The tool list handed to the AI wires (Ai::Wire::OpenAiChat /
  # Ai::Wire::AnthropicMessages both accept `tools: [{name:, description:,
  # input_schema:}, ...]`) — every read-only MCP tool from
  # Pito::Mcp::Registry, PLUS the two TERMINAL tools the orchestrator's loop
  # protocol needs to end a turn:
  #
  #   * pito_render_command — run one pito command and let its native
  #     output BE the answer (no prose alongside it).
  #   * pito_respond         — compose a structured answer out of typed
  #     blocks (text/tables/media/charts/…) instead of a prose paragraph.
  #
  # `tools` is a pure projection over Pito::Mcp::Registry, which itself
  # mirrors config/pito/verbs.yml (Config.data is reload!-cleared in
  # dev/tests) — recomputed on every call, NEVER memoized here.
  module Toolset
    module_function

    RENDER_COMMAND = "pito_render_command"
    RESPOND = "pito_respond"

    # [{name:, description:, input_schema:}, …] — Pito::Mcp::Registry.tools
    # (inputSchema → input_schema, annotations dropped — the wires don't
    # take them) followed by the two terminal tools.
    def tools
      mcp_tools + [ render_command_tool, respond_tool ]
    end

    # True for either terminal tool name — the orchestrator stops the loop
    # once one of these fires instead of feeding the result back in.
    def terminal?(name)
      name.to_s == RENDER_COMMAND || name.to_s == RESPOND
    end

    # Every declared tool name (MCP tools + the two terminals), in `tools`
    # wire order.
    def tool_names
      tools.map { |t| t[:name] }
    end

    # ── internals ──────────────────────────────────────────────────────────

    def mcp_tools
      Pito::Mcp::Registry.tools.map do |t|
        { name: t[:name], description: t[:description], input_schema: t[:inputSchema] }
      end
    end

    def render_command_tool
      {
        name: RENDER_COMMAND,
        description: "End your turn by running ONE pito command whose native output IS the answer the user should see (e.g. show game 79). Send no prose with it.",
        input_schema: {
          "type" => "object",
          "properties" => {
            "command" => {
              "type" => "string",
              "description" => "a complete pito chat command, exactly as a user would type it"
            }
          },
          "required" => [ "command" ],
          "additionalProperties" => false
        }
      }
    end

    # The whole document — block types, data shapes, guidance, content rules —
    # generates from config/pito/content.yml (Ai::ContentRegistry). Adding a
    # block or changing a rule happens THERE plus its support code, never here.
    def respond_tool
      {
        name: RESPOND,
        description: Ai::ContentRegistry.respond_description,
        input_schema: {
          "type" => "object",
          "properties" => {
            "blocks" => {
              "type" => "array",
              "minItems" => 1,
              "maxItems" => Ai::ContentRegistry.limit("max_blocks", default: 12),
              "items" => {
                "type" => "object",
                "properties" => {
                  "type" => {
                    "type" => "string",
                    "enum" => Ai::ContentRegistry.block_types
                  }
                },
                "required" => [ "type" ],
                "additionalProperties" => true
              }
            }
          },
          "required" => [ "blocks" ],
          "additionalProperties" => false
        }
      }
    end
  end
end
