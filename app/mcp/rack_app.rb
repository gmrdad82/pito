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

      token  = result.token
      tenant = token.tenant
      user   = token.user

      # Phase 7.5 — defense-in-depth tenant boundary check. ApiToken
      # has matching `tenant_id` and `user.tenant_id` by construction;
      # for Doorkeeper-issued OAuth tokens the resource owner is set
      # at consent time so the same invariant holds. If a row mutation
      # somehow desyncs the two (manual SQL, future cross-tenant
      # plumbing), refuse the request rather than serve cross-tenant.
      if user.nil? || user.tenant_id != tenant&.id
        return Api::TokenAuthenticator::Result
          .new(failure_reason: "invalid_token")
          .to_rack_response
      end

      Current.token  = token
      Current.tenant = tenant
      Current.user   = user

      @transport.call(env)
    ensure
      Current.reset
    end
  end
end
