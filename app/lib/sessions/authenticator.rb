# Phase 12 — Step A (6a-sessions-and-login-ui.md) — cookie-session
# resolver.
#
# Input is the request, output is a
# Result struct (success / failure + reason). Never raises on auth-flow
# control paths; misconfiguration of the pepper falls through to a
# `failure(:auth_misconfigured)` shape so callers can render a clean
# 500 instead of crashing the request.
#
# The caller (`Sessions::AuthConcern`) is responsible for populating
# `Current.session / .user / .tenant` and calling
# `session.touch_activity!` on success.
module Sessions
  class Authenticator
    Result = Struct.new(:session, :reason, keyword_init: true) do
      def success? = reason.nil?
      def failure? = !success?
    end

    COOKIE_NAME = :pito_session

    def self.call(request)
      new(request).call
    end

    def initialize(request)
      @request = request
    end

    def call
      plaintext = read_cookie
      return failure(:missing) if plaintext.blank?

      digest =
        begin
          Pito::TokenDigest.call(plaintext)
        rescue Api::AuthConfigurationMissing
          return Result.new(reason: :auth_misconfigured)
        end

      session = ::Session.unscoped.find_by(token_digest: digest)
      return failure(:unknown_token) unless session

      return failure(:revoked, session: session) if session.revoked?

      Result.new(session: session, reason: nil)
    end

    private

    def read_cookie
      cookie_jar = @request.cookie_jar
      cookie_jar.signed[COOKIE_NAME].presence
    rescue StandardError
      # A tampered cookie raises `ActiveSupport::MessageVerifier::InvalidSignature`
      # at read time. Treat as missing — the auth concern redirects to /login.
      nil
    end

    def failure(reason, session: nil)
      Result.new(session: session, reason: reason)
    end
  end
end
