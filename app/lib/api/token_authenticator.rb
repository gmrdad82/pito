# Phase 3 — Step B (5b-token-and-auth-concern.md) — Rack-level token auth.
#
# The single piece of code that turns a Rack `env` into either a populated
# `ApiToken` or a structured failure. Both the Rails controller concern
# (`Api::AuthConcern`) and the MCP rack app (`Mcp::RackApp`) call into it.
#
# Why a plain class instead of Rack middleware: middleware lives in the
# stack-build phase and would have to apply globally; we want the auth
# decision to be invoked only on the endpoints that need it (the MCP rack
# app, every `Api::*` controller — but NOT the cookie-based HTML routes).
# A plain class keeps the wiring explicit.
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
        [ status, { "Content-Type" => "application/json" }, [ body.to_json ] ]
      end
    end

    BEARER_RE = /\ABearer\s+(.+)\z/.freeze

    def self.call(env)
      new(env).call
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

      token = ApiToken.unscoped.find_by(token_digest: digest)

      unless token
        return failure("invalid_token")
      end

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
      Result.new(token: token, failure_reason: nil)
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
        token_name: token&.name,
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
