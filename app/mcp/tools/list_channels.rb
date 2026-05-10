module Mcp
  module Tools
    class ListChannels < MCP::Tool
      tool_name "list_channels"
      description "List YouTube channels by URL. Optional filter: star. Paginated. Returns summary JSON for each channel."

      input_schema(
        type: "object",
        properties: {
          star:   { type: "string", enum: [ "yes", "no" ], description: "Filter by star flag — 'yes' for starred only, 'no' for non-starred only (optional)" },
          limit:  { type: "integer", description: "Max results (default 50, max 200)" },
          offset: { type: "integer", description: "Offset into result set (default 0)" }
        }
      )

      annotations(read_only_hint: true)

      def self.call(star: nil, limit: 50, offset: 0)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        limit = [ [ limit.to_i, 1 ].max, 200 ].min
        offset = [ offset.to_i, 0 ].max

        # Each boolean filter uses the yes/no boundary convention. Reject
        # any value that is not exactly the string "yes" or "no" (any case).
        unless star.nil?
          unless YesNo.yes_no?(star)
            return error_response("star must be 'yes' or 'no' (got #{star.inspect})")
          end
        end

        scope = Channel.all
        scope = scope.where(star: YesNo.from_yes_no(star)) unless star.nil?

        # `created_at desc` gives fresh-first ordering (most recently added at top).
        channels = scope.order(created_at: :desc).limit(limit).offset(offset)

        data = channels.map { |c| ChannelDecorator.new(c).as_summary_json }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
