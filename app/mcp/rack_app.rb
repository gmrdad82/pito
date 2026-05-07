require "mcp"
require "mcp/server/transports/streamable_http_transport"
require_relative "pito_server"

module Mcp
  # Rack app wrapping the MCP StreamableHTTPTransport.
  # Mounted at /mcp in routes.rb, served by a dedicated Puma process (bin/mcp-web).
  #
  # Phase 3 — Step B (5b-token-and-auth-concern.md). Bearer-token auth is
  # now enforced via `Api::TokenAuthenticator`. Requests without a valid
  # token return 401; tokens that authenticate but lack the required
  # scope are rejected by individual tools via `Mcp::ToolAuth.require_scope!`.
  class RackApp
    def initialize
      server = PitoServer.build
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        enable_json_response: true
      )
    end

    def call(env)
      result = Api::TokenAuthenticator.call(env)
      return result.to_rack_response if result.failure?

      Current.token  = result.token
      Current.tenant = result.token.tenant
      Current.user   = result.token.user

      @transport.call(env)
    ensure
      Current.reset
    end
  end
end
