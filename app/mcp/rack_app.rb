require "mcp"
require "mcp/server/transports/streamable_http_transport"
require_relative "pito_server"

module Mcp
  # Rack app wrapping the MCP StreamableHTTPTransport.
  # Mounted at /mcp in routes.rb, served by a dedicated Puma process (bin/mcp-web).
  #
  # Phase 3 — Step B (5b-token-and-auth-concern.md). Bearer-token auth is
  # enforced via `Api::TokenAuthenticator`. Requests without a valid
  # token return 401; tokens that authenticate but lack the required
  # scope are rejected by individual tools via
  # `Mcp::ToolAuth.require_scope!`.
  #
  # Phase 8 — tenant drop (ADR 0003). The cross-tenant defense-in-depth
  # check is gone (single install). A token whose user row has been
  # deleted is still rejected as `invalid_token`.
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

      token = result.token
      user  = token.user

      if user.nil?
        return Api::TokenAuthenticator::Result
          .new(failure_reason: "invalid_token")
          .to_rack_response
      end

      Current.token = token
      Current.user  = user

      @transport.call(env)
    ensure
      Current.reset
    end
  end
end
