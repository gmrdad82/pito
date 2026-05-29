# Phase 12 — Step A — shared HMAC-SHA256 token digest.
#
# Single source of truth for `HMAC-SHA256(:tokens.pepper, plaintext)` used
# by `ApiToken` to digest opaque tokens before storing in the database.
module Pito
  module TokenDigest
    module_function

    # Resolve the HMAC pepper. Three-tier fallback so CI (which has no
    # `config/master.key`) can still run specs while production remains
    # fail-fast:
    #
    #   1. `Rails.application.credentials.dig(:tokens, :pepper)` —
    #      canonical production source.
    #   2. `ENV["PITO_TOKENS_PEPPER"]` — escape hatch for environments
    #      that provision secrets via env (CI, hosted runners).
    #   3. A fixed test-only constant when `Rails.env.test?` so the
    #      specs compute deterministic digests without a master key.
    def pepper
      Rails.application.credentials.dig(:tokens, :pepper) ||
        ENV["PITO_TOKENS_PEPPER"] ||
        (Rails.env.test? ? "test-pepper-not-a-secret" : nil)
    end

    # Compute `HMAC-SHA256(pepper, plaintext)` and return a hex string.
    # Raises `Api::AuthConfigurationMissing` if no pepper is resolvable
    # (matches the existing ApiToken contract). Callers may pass an
    # explicit `pepper:` to override the default resolver — used by
    # `ApiToken.digest` so the existing `ApiToken.pepper` stub
    # continues to control the digest path. Pass `:default` (the
    # default) to use the helper's own resolver.
    def call(plaintext, pepper: :default)
      pepper_value = pepper == :default ? self.pepper : pepper
      if pepper_value.blank?
        raise Api::AuthConfigurationMissing,
              "tokens.pepper credential is not set"
      end

      OpenSSL::HMAC.hexdigest("SHA256", pepper_value, plaintext.to_s)
    end
  end
end
