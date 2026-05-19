# Phase 3 — Step B (5b-token-and-auth-concern.md) — Rack-level token auth.
#
# The single piece of code that turns a Rack `env` into either a populated
# `ApiToken` or a structured failure. The Rails controller concern
# (`Api::AuthConcern`) calls into it for every `Api::*` controller.
#
# Why a plain class instead of Rack middleware: middleware lives in the
# stack-build phase and would have to apply globally; we want the auth
# decision to be invoked only on the endpoints that need it (every
# `Api::*` controller — but NOT the cookie-based HTML routes). A plain
# class keeps the wiring explicit.
#
# Failure paths set `env["pito.auth_failed"] = true` so the rack-attack
# throttle counts only failures; successful lookups don't burn the bucket.
#
# Every code path writes one JSON line to `log/auth_audit.log` via
# `AUTH_AUDIT_LOGGER` (configured in `config/initializers/auth_audit_logger.rb`).
module Api
  class TokenAuthenticator
    Result = Struct.new(:token, :failure_reason, keyword_init: true) do
      def success? = failure_reason.nil?
      def failure? = !success?

      # Rack triplet for the failure case. The auth concern uses Rails
      # rendering instead, so this helper exists only for the Rack app.
      def to_rack_response
        body = case failure_reason
        when "rate_limited"
                 { error: "rate_limited" }
        when "auth_misconfigured"
                 { error: "auth_misconfigured" }
        else
                 { error: failure_reason }
        end
        status = case failure_reason
        when "rate_limited"       then 429
        when "auth_misconfigured" then 500
        else                            401
        end
        headers = { "Content-Type" => "application/json" }

        # RFC 9728 §5.3 — every 401 from a protected resource includes a
        # `WWW-Authenticate: Bearer ...` challenge that points clients
        # at the OAuth metadata documents.
        if status == 401
          headers["WWW-Authenticate"] = Api::TokenAuthenticator.www_authenticate_header
        end

        [ status, headers, [ body.to_json ] ]
      end
    end

    BEARER_RE = /\ABearer\s+(.+)\z/.freeze

    def self.call(env)
      new(env).call
    end

    # Single source of truth for the `WWW-Authenticate: Bearer ...`
    # challenge header emitted on every 401 from the bearer-authed
    # API surface. Points clients at the OAuth authorization-server
    # metadata document for discovery.
    def self.www_authenticate_header
      app = Pito::PublicHosts.app_base
      %(Bearer realm="pito", as_uri="#{app}/.well-known/oauth-authorization-server")
    end

    def initialize(env)
      @env = env
    end

    # Returns a `Result`. Never raises (except for the misconfiguration
    # path, where we return a `Result` with `auth_misconfigured`).
    def call
      header = @env["HTTP_AUTHORIZATION"].to_s
      match = header.match(BEARER_RE)

      unless match
        return failure("missing_token")
      end

      plaintext = match[1].to_s.strip
      if plaintext.empty?
        return failure("missing_token")
      end

      digest =
        begin
          ApiToken.digest(plaintext)
        rescue Api::AuthConfigurationMissing
          audit("auth.misconfigured", token: nil, scope_required: nil, result: "auth_misconfigured")
          return Result.new(failure_reason: "auth_misconfigured")
        end

      token = ApiToken.find_by(token_digest: digest)

      if token
        # Constant-time compare — the DB lookup already keyed on the digest,
        # but the spec's locked decision wires this in for any future code
        # path that compares plaintext-to-plaintext.
        unless ActiveSupport::SecurityUtils.secure_compare(token.token_digest, digest)
          return failure("invalid_token")
        end

        if token.revoked?
          return failure("revoked_token", token: token)
        end

        if token.expired?
          return failure("expired_token", token: token)
        end

        token.touch_used!
        audit("auth.success", token: token, scope_required: nil, result: "ok")
        return Result.new(token: token, failure_reason: nil)
      end

      # Phase 7.5 — Doorkeeper fallback. The plaintext bearer was not an
      # `ApiToken` (no row matched the HMAC digest); try
      # `OauthAccessToken.by_token` next so Doorkeeper-issued access
      # tokens (via `/oauth/token`) can authenticate against `Api::*`
      # surfaces using the same bearer dispatch as ApiToken users.
      #
      # Distinct revoked / expired branches mirror the ApiToken paths so
      # the existing 401 envelopes (`revoked_token`, `expired_token`)
      # remain stable. Anything else maps to `invalid_token`.
      oauth_token = lookup_oauth_token(plaintext)
      if oauth_token
        if oauth_token.revoked?
          return failure("revoked_token", token: oauth_token)
        end

        if oauth_token.expired?
          return failure("expired_token", token: oauth_token)
        end

        unless oauth_token.resource_owner_id.present?
          # Defense-in-depth: a token without a resource owner cannot
          # be safely dispatched. Treat as invalid.
          return failure("invalid_token", token: oauth_token)
        end

        audit("auth.success", token: oauth_token, scope_required: nil, result: "ok")
        return Result.new(token: oauth_token, failure_reason: nil)
      end

      failure("invalid_token")
    end

    private

    def failure(reason, token: nil)
      @env["pito.auth_failed"] = true
      ip = client_ip
      ApiAuthThrottle.record_failure(ip) if defined?(ApiAuthThrottle)
      audit("auth.#{reason}", token: token, scope_required: nil, result: reason)
      Result.new(token: nil, failure_reason: reason)
    end

    def audit(event, token:, scope_required:, result:)
      payload = {
        ts: Time.now.utc.iso8601(3),
        event: event,
        token_id: token&.id,
        token_name: token_label(token),
        ip: client_ip,
        route: route_label,
        scope_required: scope_required,
        result: result
      }
      AUTH_AUDIT_LOGGER.info(payload.to_json)
    rescue StandardError
      # Audit logging must never break the request path.
      nil
    end

    # Best-effort human label for the audit row. `ApiToken` carries an
    # operator-supplied `name`; Doorkeeper's `OauthAccessToken` carries
    # an `application_id` instead — fall back to the application's name
    # for OAuth, and `nil` if neither path is available.
    def token_label(token)
      return nil if token.nil?
      return token.name if token.is_a?(ApiToken)
      return token.application&.name if token.respond_to?(:application)

      nil
    end

    # Doorkeeper bearer-token lookup. Returns the `OauthAccessToken`
    # row (which subclasses `Doorkeeper::AccessToken`) or `nil`. Wrapped
    # in a guard so request flows that pre-date Doorkeeper (e.g. specs
    # that boot a stubbed environment) keep working without raising.
    def lookup_oauth_token(plaintext)
      return nil unless defined?(OauthAccessToken)

      OauthAccessToken.by_token(plaintext)
    rescue StandardError
      nil
    end

    def client_ip
      @env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
        @env["REMOTE_ADDR"] ||
        "-"
    end

    def route_label
      method = @env["REQUEST_METHOD"]
      path   = @env["PATH_INFO"]
      [ method, path ].compact.join(" ").strip
    end
  end
end
