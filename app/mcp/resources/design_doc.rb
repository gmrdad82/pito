module Mcp
  module Resources
    module DesignDoc
      URI_PREFIX = "pito://design"

      def self.definitions
        [
          MCP::Resource.new(
            uri: URI_PREFIX,
            name: "design system",
            description: "Pito design system — colors, typography, components, layout conventions",
            mime_type: "text/markdown"
          )
        ]
      end

      def self.handles?(uri)
        uri == URI_PREFIX
      end

      def self.read(uri)
        content = File.read(Rails.root.join("docs/design.md"))
        [ { uri: uri, mimeType: "text/markdown", text: content } ]
      end
    end
  end
end
