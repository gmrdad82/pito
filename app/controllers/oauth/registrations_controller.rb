# RFC 7591 — OAuth 2.0 Dynamic Client Registration Protocol.
#
# Doorkeeper 5.9 does not ship a DCR endpoint. The MCP SDK that ships
# with the Claude CLI refuses to authenticate against an AS that does
# not advertise a `registration_endpoint`; without this controller the
# CLI errors with:
#
#   SDK auth failed: Incompatible auth server: does not support
#   dynamic client registration
#
# This controller is the minimum viable RFC 7591 surface. It accepts a
# JSON registration request and creates an `OauthApplication`, then
# echoes the canonical client metadata back. Per RFC 7591 §3.2.1 the
# response includes the `client_id`, the freshly minted `client_secret`
# (for confidential clients), `client_id_issued_at`, and
# `client_secret_expires_at` (0 = never expires, which matches the rest
# of pito — Doorkeeper does not rotate client secrets on a schedule).
#
# Authentication: anonymous. RFC 7591 §3 defines an optional
# "initial access token" gating mechanism; for a single-user pito
# install behind cloudflared we leave the endpoint open and rely on
# (a) the per-IP `oauth/register` Rack::Attack throttle in
# `config/initializers/rack_attack.rb`, and (b) the user-consent
# screen that still runs on every `/oauth/authorize`. Registering a
# client grants exactly zero ability to act on the user's behalf
# until the user has clicked through consent — registration is just
# "I would like to ask, please".
#
# CSRF: skipped (`skip_forgery_protection`). The endpoint is meant to
# be hit by non-browser OAuth clients (MCP SDKs, CLI tools) that have
# no cookie / no CSRF token; RFC 7591 explicitly defines a JSON POST
# with no session state.
class Oauth::RegistrationsController < ApplicationController
  # The cookie-session before_action defaults to redirecting
  # unauthenticated callers to /login. DCR is bearer-less; skip both
  # the session redirect and the CSRF check.
  skip_before_action :authenticate_session!
  skip_before_action :verify_authenticity_token, raise: false
  skip_forgery_protection

  # POST /oauth/register
  #
  # Request body (JSON, RFC 7591 §2):
  #   {
  #     "redirect_uris": ["https://client.example.org/callback"],
  #     "client_name": "Example Client",
  #     "token_endpoint_auth_method": "none" | "client_secret_basic" | "client_secret_post",
  #     "grant_types": ["authorization_code", "refresh_token"],
  #     "response_types": ["code"],
  #     "scope": "app"
  #   }
  #
  # Response (201 Created, RFC 7591 §3.2.1):
  #   {
  #     "client_id": "<uid>",
  #     "client_secret": "<secret>",          // omitted for public clients
  #     "client_id_issued_at": <unix-ts>,
  #     "client_secret_expires_at": 0,        // 0 = no expiration
  #     ...all client_metadata echoed back
  #   }
  #
  # Errors (RFC 7591 §3.2.2): JSON `{ "error": "...", "error_description": "..." }`
  # with HTTP 400. Only two error codes are in scope here:
  #   * `invalid_redirect_uri`     — `redirect_uris` missing / malformed / fails
  #                                  Doorkeeper's RedirectUriValidator.
  #   * `invalid_client_metadata`  — anything else (bad scope, bad grant_type,
  #                                  ActiveRecord validation failure that is
  #                                  not redirect-URI-shaped).
  def create
    body = parse_request_body
    return render_error(:invalid_client_metadata, "request body must be JSON") unless body.is_a?(Hash)

    redirect_uris = Array(body["redirect_uris"]).map(&:to_s).reject(&:blank?)
    if redirect_uris.empty?
      return render_error(:invalid_redirect_uri, "redirect_uris is required and must contain at least one URI")
    end

    # RFC 7591 §2: `token_endpoint_auth_method` defaults to
    # `client_secret_basic`. The MCP SDK's PKCE-public-client flow
    # explicitly requests `"none"`; we honor it. Anything else maps
    # to a confidential client (Doorkeeper stores `confidential =
    # true` and requires the secret on token exchange).
    auth_method = body["token_endpoint_auth_method"].presence || "client_secret_basic"
    confidential = auth_method != "none"

    client_name = body["client_name"].to_s.strip
    client_name = "dcr-client-#{SecureRandom.hex(4)}" if client_name.blank?

    # Scope handling: RFC 7591 §2 sends scopes as a single
    # space-separated string. We clip to the configured catalog so a
    # malformed registration cannot widen the scope surface beyond
    # what `Scopes::ALL` advertises. Empty `scope` lets Doorkeeper
    # fall through to its configured default scopes at /oauth/token
    # time.
    requested_scopes = body["scope"].to_s.split(/\s+/).reject(&:blank?)
    invalid_scopes = requested_scopes - Scopes::ALL
    if invalid_scopes.any?
      return render_error(
        :invalid_client_metadata,
        "unknown scope(s): #{invalid_scopes.join(' ')}"
      )
    end

    application = OauthApplication.new(
      name: client_name,
      redirect_uri: redirect_uris.join(" "),
      scopes: requested_scopes.join(" "),
      confidential: confidential
    )

    unless application.save
      code = redirect_uri_error?(application) ? :invalid_redirect_uri : :invalid_client_metadata
      return render_error(code, application.errors.full_messages.join("; "))
    end

    render json: registration_response(application, body), status: :created
  end

  private

  def parse_request_body
    raw = request.raw_post
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def redirect_uri_error?(application)
    application.errors.any? { |err| err.attribute == :redirect_uri }
  end

  # RFC 7591 §3.2.2 — error response shape.
  def render_error(code, description)
    render json: { error: code.to_s, error_description: description }, status: :bad_request
  end

  # RFC 7591 §3.2.1 — successful registration response.
  #
  # `client_secret_expires_at: 0` is the RFC's "never expires"
  # sentinel. Doorkeeper does not rotate client secrets on a TTL; the
  # operator-only `bin/rails pito:oauth_apps:*` task is the rotation
  # surface.
  #
  # The plaintext secret is only available on the `OauthApplication`
  # instance immediately after `save` (Doorkeeper hashes it on the
  # next reload). We pull it via `plaintext_secret`.
  def registration_response(application, body)
    response = {
      client_id: application.uid,
      client_id_issued_at: application.created_at.to_i,
      client_secret_expires_at: 0,
      redirect_uris: application.redirect_uri.to_s.split,
      grant_types: %w[authorization_code refresh_token],
      response_types: %w[code],
      token_endpoint_auth_method: application.confidential? ? "client_secret_basic" : "none",
      client_name: application.name,
      scope: application.scopes.to_s
    }

    response[:client_secret] = application.plaintext_secret if application.confidential?

    # Echo back any RFC 7591 metadata fields the client sent that we
    # do not persist (logo_uri, client_uri, etc.). RFC 7591 §3.2.1
    # explicitly allows the AS to return additional client metadata
    # that was registered; round-tripping is the friendliest
    # default for SDKs that compare request vs response.
    %w[client_uri logo_uri tos_uri policy_uri contacts software_id software_version].each do |key|
      response[key.to_sym] = body[key] if body[key].present?
    end

    response
  end
end
