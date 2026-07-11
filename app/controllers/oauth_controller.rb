# frozen_string_literal: true

# The hand-rolled OAuth 2.1 authorization server for MCP. Public clients
# only (PKCE, no client_secret). Anonymous at the HTTP layer — the AUTHORIZATION
# is gated by TOTP at consent (the owner's single approval per client), not by a
# cookie session. register/token are JSON APIs (the client's server); authorize/
# approve are the owner's browser consent page.
#
# Security invariants: exact-match redirect URIs (no open redirect), PKCE S256
# MANDATORY, single-use 5-minute codes, TOTP + throttle at consent, tokens stored
# as digests only. See OauthClient / OauthCode / OauthToken.
class OauthController < ApplicationController
  allow_anonymous :register, :authorize, :approve, :token
  # register/token are server-to-server (the client's backend, no cookie, no CSRF
  # token) — exempt them. `approve` is a browser form and KEEPS CSRF protection.
  skip_forgery_protection only: %i[register token]
  layout "oauth"

  # ── POST /oauth/register — RFC 7591 dynamic registration (JSON) ──────────────
  def register
    uris = Array(params[:redirect_uris]).map(&:to_s)
    return render json: { error: "invalid_redirect_uri" }, status: :bad_request if uris.empty? || uris.any? { |u| !valid_redirect?(u) }

    client = OauthClient.register(name: params[:client_name], redirect_uris: uris)
    render json: {
      client_id:                  client.client_id,
      client_id_issued_at:        client.created_at.to_i,
      client_name:                client.name,
      redirect_uris:              client.redirect_uris,
      grant_types:                %w[authorization_code refresh_token],
      response_types:             %w[code],
      token_endpoint_auth_method: "none"
    }, status: :created
  end

  # ── GET /oauth/authorize — the owner's consent page ──────────────────────────
  def authorize
    return unless validate_authorize_request

    @tools = Pito::Mcp::Registry.tools
  end

  # ── POST /oauth/authorize — TOTP consent → mint code → redirect back ─────────
  def approve
    return unless validate_authorize_request

    ip = request.remote_ip.to_s
    return deny("Too many attempts — wait a few minutes and retry.") if SessionThrottle.exhausted?(ip)

    unless Pito::Auth::TotpVerifier.call(code: params[:totp_code]) == :ok
      SessionThrottle.record_failure(ip)
      return deny("That code didn't match. Try the current code from your authenticator.")
    end

    raw_code, = OauthCode.mint(
      client_id:      @client.client_id,
      redirect_uri:   @redirect_uri,
      code_challenge: params[:code_challenge],
      code_challenge_method: "S256"
    )
    redirect_to redirect_back(code: raw_code, state: params[:state]), allow_other_host: true
  end

  # ── POST /oauth/token — code / refresh grant (JSON) ──────────────────────────
  def token
    case params[:grant_type]
    when "authorization_code" then grant_authorization_code
    when "refresh_token"      then grant_refresh_token
    else render json: { error: "unsupported_grant_type" }, status: :bad_request
    end
  end

  private

  # Validates client + redirect + response_type + PKCE for the authorize/approve
  # pair. Renders/redirects the appropriate error and returns false when invalid;
  # sets @client and returns true when the request is well-formed.
  def validate_authorize_request
    @client = OauthClient.find_by(client_id: params[:client_id].to_s)
    if @client.nil?
      render_consent_error("Unknown client.")
      return false
    end

    # A bad/unregistered redirect can NOT be redirected to (that IS the attack) —
    # show an on-page error instead of bouncing to an attacker-chosen URL.
    unless @client.allows_redirect?(params[:redirect_uri].to_s)
      render_consent_error("This redirect URI is not registered for the client.")
      return false
    end

    # Pin the redirect target to the CLIENT-REGISTERED URI (from the model), not the
    # raw param — they're equal (allows_redirect? just confirmed it), but redirecting
    # to the stored value means we NEVER bounce to an attacker-shaped param string.
    @redirect_uri = @client.redirect_uris.find { |uri| uri == params[:redirect_uri].to_s }

    # From here the redirect_uri is trusted, so protocol errors go BACK to it.
    unless params[:response_type].to_s == "code"
      redirect_error("unsupported_response_type")
      return false
    end
    unless pkce_present?
      redirect_error("invalid_request")
      return false
    end

    true
  end

  def grant_authorization_code
    code = OauthCode.claim(params[:code])
    return render json: { error: "invalid_grant" }, status: :bad_request if code.nil?
    return render json: { error: "invalid_grant" }, status: :bad_request unless
      code.valid_exchange?(client_id: params[:client_id].to_s, redirect_uri: params[:redirect_uri].to_s, code_verifier: params[:code_verifier])

    access, refresh, record = OauthToken.issue(client_id: code.client_id)
    render json: token_response(access_token: access, refresh_token: refresh, record: record)
  end

  def grant_refresh_token
    result = OauthToken.refresh!(params[:refresh_token])
    return render json: { error: "invalid_grant" }, status: :bad_request if result.nil?

    new_access, record = result
    # The refresh token is unchanged (it never expires; only revocation kills it).
    render json: token_response(access_token: new_access, refresh_token: params[:refresh_token], record: record)
  end

  def token_response(access_token:, refresh_token:, record:)
    {
      access_token:  access_token,
      refresh_token: refresh_token,
      token_type:    "Bearer",
      expires_in:    [ (record.expires_at - Time.current).to_i, 0 ].max
    }
  end

  # ── consent rendering ────────────────────────────────────────────────────────

  def render_consent_error(message)
    @error = message
    render :error, status: :bad_request
  end

  def deny(message)
    @error  = message
    @tools  = Pito::Mcp::Registry.tools
    render :authorize, status: :unauthorized
  end

  # ── redirect helpers (redirect_uri is validated before any of these) ─────────

  def redirect_back(code:, state:)
    build_redirect(@redirect_uri, code: code, state: state.presence)
  end

  def redirect_error(error)
    redirect_to build_redirect(@redirect_uri, error: error, state: params[:state].presence),
                allow_other_host: true
  end

  def build_redirect(base, **extra)
    uri   = URI.parse(base.to_s)
    query = URI.decode_www_form(uri.query || "")
    extra.each { |k, v| query << [ k.to_s, v ] unless v.nil? }
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  # ── validation helpers ───────────────────────────────────────────────────────

  def pkce_present?
    params[:code_challenge].present? && params[:code_challenge_method].to_s == "S256"
  end

  # HTTPS everywhere; http only for loopback (local development / native clients).
  def valid_redirect?(uri)
    parsed = URI.parse(uri.to_s)
    return true if parsed.is_a?(URI::HTTPS) && parsed.host.present?

    parsed.is_a?(URI::HTTP) && %w[localhost 127.0.0.1].include?(parsed.host)
  rescue URI::InvalidURIError
    false
  end
end
