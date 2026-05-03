module Mcp
  module Tools
    class SearchContent < MCP::Tool
      tool_name "search"
      description "Full-text search across videos using Meilisearch. Returns matched results with highlights. (Channels are not searchable in Phase B — their searchable surface returns once YouTube sync ships and channels have synced metadata.)"

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
        videos = engine.search(Video, query, page: page, per_page: per_page)

        # Match the flat SearchResults shape consumed by the Rust client:
        #   { query, videos: [SearchHit<Video>], video_total, took_ms }
        # where each hit is { record: <Video summary>, highlights }.
        # Hits whose backing Video row is missing are dropped — the Rust
        # `SearchHit::record` field is non-nullable.
        hit_payload = videos[:hits].filter_map do |hit|
          record = hit[:record]
          next nil unless record
          {
            record: VideoDecorator.new(record).as_summary_json,
            highlights: stringify_highlights(hit[:highlights])
          }
        end

        data = {
          query: query,
          videos: hit_payload,
          video_total: videos[:total].to_i,
          took_ms: videos[:took_ms].to_f
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      rescue => e
        MCP::Tool::Response.new([ { type: "text", text: "search error: #{e.message}" } ], error: true)
      end

      # Coerce Meilisearch's `_formatted` payload into the Rust-friendly
      # `HashMap<String, String>` shape (arrays joined, non-strings stringified).
      def self.stringify_highlights(raw)
        return {} unless raw.is_a?(Hash)
        raw.each_with_object({}) do |(k, v), out|
          out[k.to_s] = case v
          when String then v
          when Array  then v.join(", ")
          else v.to_s
          end
        end
      end
    end
  end
end
