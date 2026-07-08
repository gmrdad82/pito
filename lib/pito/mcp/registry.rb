# frozen_string_literal: true

module Pito
  module Mcp
    # The MCP tool ontology, read from the SAME config/pito/verbs.yml the chat
    # dispatcher uses (owner rule 4: verbs.yml is the ONLY place a tool is declared
    # — no Ruby verb→tool table). Two sources, one registry:
    #
    #   * per-verb `mcp:` blocks — a READ-ONLY chat verb promoted to a tool. The
    #     Executor builds a grammar string from `input` + `input_suffixes` and
    #     routes it through Pito::Dispatch::Router (T2.2).
    #   * top-level `mcp_readers:` — tools with no backing verb (pito_conversations
    #     / pito_messages); they SELECT persisted rows, no dispatch.
    #
    # `tools` is the MCP `tools/list` payload (name + description + JSON-Schema
    # `inputSchema` derived from `params`). `tool(name)` returns the full internal
    # descriptor the Executor consumes (kind, backing verb, input template, params).
    #
    # Nothing here persists, enqueues, or mutates — it is a pure projection of the
    # frozen config document, recomputed each call so it always mirrors the current
    # verbs.yml (Config.data is memoized + reload!-cleared in dev/tests, so the
    # add-a-tool proof can inject a synthetic tool and see it here).
    module Registry
      module_function

      # MCP tools/list — [{ name:, description:, inputSchema: }], name-sorted for a
      # stable wire order (the TOOL MATRIX pins this against the declarations).
      def tools
        descriptors.values.map do |d|
          { name: d[:name], description: d[:description], inputSchema: input_schema(d[:params]) }
        end
      end

      # The full internal descriptor for one tool, or nil when the name is unknown.
      #   { name:, description:, kind: :verb|:reader, verb:, input:, input_suffixes:, params: }
      def tool(name)
        descriptors[name.to_s]
      end

      # Every declared tool name (verb tools + readers), name-sorted.
      def tool_names
        descriptors.keys
      end

      # ── internals ──────────────────────────────────────────────────────────────

      # name(String) → descriptor Hash, merged from the verb `mcp:` blocks and the
      # top-level `mcp_readers:`. Cheap (a map over ~13 entries); recomputed each
      # call so it tracks Config.reload!.
      def descriptors
        data    = Pito::Dispatch::Config.data
        verbs   = data.fetch(:verbs, {})
        readers = data.fetch(:mcp_readers, {})
        out     = {}

        verbs.each do |verb, body|
          block = body.is_a?(Hash) && body[:mcp]
          next unless block

          out[block[:tool].to_s] = {
            name:           block[:tool].to_s,
            description:    block[:description].to_s,
            kind:           :verb,
            verb:           verb.to_s,
            input:          block[:input].to_s,
            input_suffixes: block[:input_suffixes] || {},
            params:         block[:params] || {}
          }
        end

        readers.each_value do |body|
          out[body[:tool].to_s] = {
            name:           body[:tool].to_s,
            description:    body[:description].to_s,
            kind:           :reader,
            verb:           nil,
            input:          nil,
            input_suffixes: {},
            params:         body[:params] || {}
          }
        end

        out.sort.to_h
      end

      # JSON-Schema object for a tool's params (MCP `inputSchema`). No params → a
      # valid no-arg object. `additionalProperties: false` so a client can't smuggle
      # extra keys past the grammar builder.
      def input_schema(params)
        properties = {}
        required   = []

        params.each do |name, spec|
          properties[name.to_s] = property_schema(spec)
          required << name.to_s if spec[:required]
        end

        schema = { "type" => "object", "properties" => properties, "additionalProperties" => false }
        schema["required"] = required unless required.empty?
        schema
      end

      # One param → its JSON-Schema fragment: `hint` → `description`, `enum` carried
      # through, an array param nests `items` (default string).
      def property_schema(spec)
        frag = { "type" => spec[:type].to_s }
        frag["description"] = spec[:hint].to_s          if spec[:hint]
        frag["enum"]        = spec[:enum].map(&:to_s)   if spec[:enum]
        frag["items"]       = { "type" => (spec[:items] || "string").to_s } if spec[:type].to_s == "array"
        frag
      end
    end
  end
end
