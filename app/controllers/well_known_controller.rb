# Phase 7.5 — MCP OAuth discovery metadata.
#
# Two public, unauthenticated JSON endpoints that Claude.ai's MCP custom
# connector probes to discover Pito's OAuth surface. Both are mounted
# at the conventional `/.well-known/...` paths (RFC 8414 + RFC 9728) and
# served by both the web Puma (`app.pitomd.com`) and the MCP Puma
# (`mcp.pitomd.com`) since they run the same Rails app.
#
#   - `oauth_authorization_server` — RFC 8414. Describes Pito-as-AS
#     (Doorkeeper-issued tokens via `app.pitomd.com/oauth/*`).
#   - `oauth_protected_resource`   — RFC 9728. Describes Pito-as-RS
#     (the MCP tool surface at `mcp.pitomd.com/mcp`) and points
#     clients back at the AS for token issuance.
#
# Hardcoded `issuer` / `resource` URLs (see `Pito::PublicHosts` for the
# why) — the values must NOT change based on `request.host`, otherwise
# a probe that lands on `mcp.pitomd.com` would advertise itself as the
# AS and break the discovery handshake.
#
# Auth: anonymous. The cookie-session concern's `allow_anonymous` API
# bypasses the `authenticate_session!` redirect; bearer-only auth is
# never wired in here.
class WellKnownController < ApplicationController
  allow_anonymous :oauth_authorization_server, :oauth_protected_resource

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
      # RFC 7591 §2 — Dynamic Client Registration endpoint. The
      # Claude CLI's MCP SDK refuses to authenticate against an AS
      # that does not advertise this field. Backed by
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
      # Some clients honor it as a courtesy — Claude.ai's MCP custom
      # connector being the motivating one — and use it to source the
      # connector list icon. Cost: one extra field. Benefit: a possible
      # icon-discovery hit on top of the layout-`<head>` shotgun.
      # 2026-05-19 — retargeted from `/Pito.png` (retired) to
      # `/android-chrome-192x192.png`, the canonical "app icon" size for
      # OAuth / PWA contexts.
      logo_uri: "#{app_base}/android-chrome-192x192.png?v=2"
    }
  end

  # GET /.well-known/oauth-protected-resource
  #
  # RFC 9728 metadata document. `resource` is the canonical RS endpoint
  # — the actual MCP HTTP transport URL, not the bare host. MCP-aware
  # clients that consult this metadata use the `resource` value as the
  # POST target, so it MUST point at `/mcp` (where `Mcp::RackApp` is
  # mounted). Phase 7.5 connector-hardening fix: previously this field
  # advertised only the host origin, which sent compliant clients to
  # `https://mcp.pitomd.com/` and produced 404s. The root-path alias
  # in `config/routes.rb` covers clients that ignore the metadata, but
  # the canonical endpoint is `/mcp`.
  #
  # `authorization_servers` advertises the AS origin clients should
  # drive the OAuth dance against — that stays at the host root since
  # Doorkeeper mounts under `/oauth/*` and the AS metadata document
  # lists its specific endpoints.
  def oauth_protected_resource
    render json: {
      resource: "#{mcp_base}/mcp",
      authorization_servers: [ app_base ],
      scopes_supported: Scopes::ALL,
      bearer_methods_supported: [ "header" ],
      # Non-standard extension (RFC 9728 doesn't define `logo_uri` for
      # protected-resource metadata). Same rationale as the AS metadata
      # field above — courtesy hint for icon-aware clients that probe
      # this surface. The asset lives at `app.pitomd.com` (the canonical
      # host) but the file resolves on `mcp.pitomd.com` too since both
      # subdomains serve the same Rails app and the favicon set is
      # served by `ActionDispatch::Static`. 2026-05-19 — retargeted from
      # `/Pito.png` (retired) to `/android-chrome-192x192.png` (canonical
      # app-icon size for OAuth / PWA contexts).
      logo_uri: "#{app_base}/android-chrome-192x192.png?v=2"
    }
  end

  private

  def app_base
    Pito::PublicHosts.app_base
  end

  def mcp_base
    Pito::PublicHosts.mcp_base
  end
end
