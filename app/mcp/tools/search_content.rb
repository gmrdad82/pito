module Mcp
  module Tools
    class SearchContent < MCP::Tool
      tool_name "search"
      description "Full-text search across channels and videos using Meilisearch. Returns matched results with highlights."

      input_schema(
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          page: { type: "integer", description: "Page number (default: 1)" },
          per_page: { type: "integer", description: "Results per section (default: 20, max: 50)" }
        },
        required: [ "query" ]
      )

      annotations(read_only_hint: true)

      def self.call(query:, page: 1, per_page: 20)
        per_page = [ [ per_page.to_i, 1 ].max, 50 ].min
        page = [ page.to_i, 1 ].max

        engine = Search.engine
        channels = engine.search(Channel, query, page: page, per_page: per_page)
        videos = engine.search(Video, query, page: page, per_page: per_page)

        data = {
          query: query,
          channels: {
            total: channels[:total],
            took_ms: channels[:took_ms],
            hits: channels[:hits].map { |h| h.except(:record) }
          },
          videos: {
            total: videos[:total],
            took_ms: videos[:took_ms],
            hits: videos[:hits].map { |h| h.except(:record) }
          }
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      rescue => e
        MCP::Tool::Response.new([ { type: "text", text: "search error: #{e.message}" } ], error: true)
      end
    end
  end
end
