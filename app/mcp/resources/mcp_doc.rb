module Mcp
  module Resources
    module McpDoc
      URI_PREFIX = "pito://mcp"

      def self.definitions
        [
          MCP::Resource.new(
            uri: URI_PREFIX,
            name: "mcp documentation",
            description: "MCP server documentation — available tools, resources, and usage patterns",
            mime_type: "text/markdown"
          )
        ]
      end

      def self.handles?(uri)
        uri == URI_PREFIX
      end

      def self.read(uri)
        path = Rails.root.join("docs/mcp.md")
        if File.exist?(path)
          content = File.read(path)
          [ { uri: uri, mimeType: "text/markdown", text: content } ]
        else
          [ { uri: uri, mimeType: "text/plain", text: "mcp.md not found" } ]
        end
      end
    end
  end
end
