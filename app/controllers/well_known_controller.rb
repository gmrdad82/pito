# frozen_string_literal: true

# OAuth discovery documents (G130) — public, unauthenticated JSON that MCP clients
# fetch to bootstrap the flow. Endpoint URLs are derived from the request host, so
# they are correct behind cloudflared regardless of the configured domain.
class WellKnownController < ApplicationController
  allow_anonymous :authorization_server, :protected_resource

  # GET /.well-known/oauth-authorization-server (RFC 8414)
  def authorization_server
    render json: {
      issuer:                                request.base_url,
      authorization_endpoint:                "#{request.base_url}/oauth/authorize",
      token_endpoint:                        "#{request.base_url}/oauth/token",
      registration_endpoint:                 "#{request.base_url}/oauth/register",
      response_types_supported:              %w[code],
      grant_types_supported:                 %w[authorization_code refresh_token],
      code_challenge_methods_supported:      %w[S256],
      token_endpoint_auth_methods_supported: %w[none]
    }
  end

  # GET /.well-known/oauth-protected-resource (RFC 9728) — points the MCP resource
  # at this same host as its authorization server.
  def protected_resource
    render json: {
      resource:              request.base_url,
      authorization_servers: [ request.base_url ]
    }
  end
end
