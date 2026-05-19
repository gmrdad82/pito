# frozen_string_literal: true

# Phase 12 — Step B (6b-doorkeeper-oauth-server.md). Doorkeeper config.
#
# `Scopes::ALL` lives under `app/lib` and is autoloaded via Zeitwerk;
# the initializer needs the constants at boot time, so we require the
# file explicitly (initializers run before autoloading is fully wired).
require Rails.root.join("app/lib/scopes.rb")
#
# Locked decisions:
#   - Authorization Code + PKCE only. Refresh tokens with rotation.
#     Implicit, ROPC, AND Client Credentials are explicitly disabled.
#   - 2h access token TTL, 14d refresh token TTL.
#   - PKCE forced for public clients (the seeded `pito-cli` is public).
#   - `Scopes::ALL` is the single source of truth. Catalog: `app`.
#     Phase 29 (MCP cut, 2026-05-19) collapsed the catalog to a single
#     scope after the dev / auth MCP surfaces were removed. Per ADR 0004
#     (with the Phase 29 update).
#   - Resource owner = the cookie-resolved current user (Phase 12 Step A).
#     `/oauth/authorize` redirects to `/login` if there is no session.
#
# Phase 8 — tenant drop. The Doorkeeper subclass models
# (`OauthApplication`, `OauthAccessToken`, `OauthAccessGrant`) are thin
# Doorkeeper subclasses with no extra scoping. Resource-owner /
# admin authentication blocks no longer pin `Current.tenant` (the
# attribute is gone).
Doorkeeper.configure do
  orm :active_record

  # Custom Doorkeeper subclasses. The Phase 8 trim removed all
  # tenant-scoping plumbing; the subclasses exist primarily so the
  # bearer dispatch (`Api::TokenAuthenticator`) can resolve the
  # `OauthAccessToken#user` reader symmetrically with `ApiToken#user`.
  application_class  "OauthApplication"
  access_token_class "OauthAccessToken"
  access_grant_class "OauthAccessGrant"

  # Resource owner = the user behind the cookie session. Doorkeeper's
  # authorization controller does NOT inherit from our
  # `ApplicationController` (it descends from `ActionController::Base`),
  # so we resolve the cookie here directly via `Sessions::Authenticator`
  # rather than relying on `Current.user` being pre-populated. This
  # block also pins `Current.user` / `Current.session` for the
  # remainder of the request so the consent screen view can render
  # `Current.user` data.
  resource_owner_authenticator do
    auth_result = Sessions::Authenticator.call(request)

    if auth_result.success?
      Current.session = auth_result.session
      Current.user    = auth_result.session.user
      auth_result.session.touch_activity!
      auth_result.session.user
    else
      cookies.signed[Sessions::AuthConcern::INTENDED_URL_COOKIE] = {
        value: request.fullpath,
        httponly: true,
        same_site: :lax,
        secure: !Rails.env.test?,
        expires: Sessions::AuthConcern::INTENDED_URL_TTL.from_now
      }
      redirect_to(main_app.login_path)
      nil
    end
  end

  # Admin authenticator — used when the bundled `applications` admin UI
  # is mounted. We skip those controllers (`skip_controllers
  # :applications, :authorized_applications` in routes.rb) and replace
  # them with `/settings/oauth_applications`, but the block still has
  # to be defined to avoid a 403 on the admin entrypoint.
  admin_authenticator do
    auth_result = Sessions::Authenticator.call(request)
    if auth_result.success?
      Current.session = auth_result.session
      Current.user    = auth_result.session.user
      Current.user
    else
      redirect_to(main_app.login_path)
    end
  end

  # Token TTLs — locked: 2h access. Doorkeeper 5.x has no first-class
  # `refresh_token_expires_in` knob; refresh-token lifetime is governed
  # by rotation (each refresh issues a new refresh token, the previous
  # one is revoked) rather than a hard TTL. The "14d refresh" target is
  # achieved practically by clients refreshing within the access-token
  # window; abandoned chains are cleaned up by the same revocation
  # cascade that runs when the application is destroyed.
  access_token_expires_in 2.hours

  # Refresh-token rotation: enabled. Every refresh issues a new refresh
  # token; the previous one is revoked as soon as the new access token
  # is created.
  use_refresh_token

  # Scopes — sourced from `Scopes::ALL`. With the Phase 29 MCP cut the
  # catalog collapsed to a single scope (`app`), which is advertised as
  # the default. Clients requesting no explicit `scope` parameter
  # receive `app` (still clipped by the soft-clip monkey-patch).
  default_scopes(*Scopes::ALL)
  optional_scopes

  # Forbid creating an application with a scope outside the catalog.
  enforce_configured_scopes

  # PKCE required for public clients. Confidential clients (none in v1)
  # may skip the challenge.
  force_pkce

  # Grant flows — Authorization Code only. Refresh tokens flow off
  # `use_refresh_token` above, not the grant_flows list. Implicit,
  # ROPC, and Client Credentials are NOT in this list — Doorkeeper
  # rejects requests for them with 400 unsupported_grant_type.
  grant_flows %w[authorization_code]

  # Always show the consent screen (no skip_authorization shortcuts).
  # `remember this app for 30 days` UX is deferred (locked decision).
  skip_authorization do |_resource_owner, _client|
    false
  end

  # Resource Owner Password Credentials and Client Credentials are NOT
  # in the `grant_flows` list above, so Doorkeeper rejects those grant
  # types with `unsupported_grant_type` before reaching any authenticator
  # block. We do not define `resource_owner_from_credentials` — the
  # grant_flows exclusion is the gate.

  # Force HTTPS in redirect URIs except in development (Cloudflare
  # tunnel runs HTTPS in dev, but the locked decision keeps a single
  # rule: `127.0.0.1` and `localhost` loopback always allowed). Test
  # env stays loose so request specs can use `http://example.org`.
  if Rails.env.production?
    force_ssl_in_redirect_uri true
  else
    force_ssl_in_redirect_uri false
  end
end
