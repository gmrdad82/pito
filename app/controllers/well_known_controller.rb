# RFC 8414 — OAuth 2.0 Authorization Server Metadata.
#
# Public, unauthenticated JSON endpoint at
# `/.well-known/oauth-authorization-server` that describes Pito-as-AS
# (Doorkeeper-issued tokens via `app.pitomd.com/oauth/*`). Survives the
# MCP cut because the OAuth surface is still wired for the Claude
# Desktop OAuth client and any future bearer-authed clients.
#
# Hardcoded `issuer` URL (see `Pito::PublicHosts`): the value MUST NOT
# change based on `request.host` so probes that land on alternate
# subdomains still report the canonical issuer.
#
# Auth: anonymous. The cookie-session concern's `allow_anonymous` API
# bypasses the `authenticate_session!` redirect.
class WellKnownController < ApplicationController
  allow_anonymous :oauth_authorization_server

  # GET /.well-known/oauth-authorization-server
  #
  # RFC 8414 metadata document. Field names match the RFC verbatim
  # (`response_types_supported`, `grant_types_supported`,
  # `code_challenge_methods_supported`, etc.). PKCE-S256 only since
  # `force_pkce` is set in the Doorkeeper initializer.
  def oauth_authorization_server
    render json: {
      issuer: app_base,
      authorization_endpoint: "#{app_base}/oauth/authorize",
      token_endpoint: "#{app_base}/oauth/token",
      revocation_endpoint: "#{app_base}/oauth/revoke",
      introspection_endpoint: "#{app_base}/oauth/introspect",
      # RFC 7591 §2 — Dynamic Client Registration endpoint. Backed by
      # `Oauth::RegistrationsController#create`.
      registration_endpoint: "#{app_base}/oauth/register",
      scopes_supported: Scopes::ALL,
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none],
      revocation_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none],
      code_challenge_methods_supported: [ "S256" ],
      # Non-standard extension (RFC 8414 doesn't define `logo_uri` for
      # AS metadata; RFC 7591 defines it for CLIENT metadata only).
      # Some clients honor it as a courtesy and use it to source the
      # connector list icon. Cost: one extra field. Benefit: a possible
      # icon-discovery hit on top of the layout-`<head>` shotgun.
      logo_uri: "#{app_base}/android-chrome-192x192.png?v=2"
    }
  end

  private

  def app_base
    Pito::PublicHosts.app_base
  end
end
