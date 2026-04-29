require "mcp"
require "mcp/server/transports/streamable_http_transport"

module Mcp
  # Rack app wrapping the MCP StreamableHTTPTransport.
  # Mounted at /mcp in routes.rb, served by a dedicated Puma process (bin/mcp-web).
  # Auth: open for now (seed data only). OAuth will be added in Beta.
  class RackApp
    def initialize
      server = PitoServer.build
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        enable_json_response: true
      )
    end

    def call(env)
      @transport.call(env)
    end
  end
end
