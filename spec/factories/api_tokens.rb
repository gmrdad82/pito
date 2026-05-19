# Phase 3 — Step B (5b-token-and-auth-concern.md).
#
# Renamed from `mcp_access_token` factory. The default factory builds a
# row with a freshly digested random plaintext, the `app` scope, and a
# freshly seeded user. Phase 8 — tenant drop: no tenant association.
# Phase 29 (MCP cut, 2026-05-19) — the dev / auth scopes were retired
# alongside the MCP surface; only `app` remains.
FactoryBot.define do
  factory :api_token do
    user
    sequence(:name) { |n| "token-#{n}" }
    scopes { [ Scopes::APP ] }

    # Set the digest from a freshly-minted plaintext so the row is
    # internally consistent (digest = HMAC(pepper, plaintext)). Specs
    # that need the plaintext should call `ApiToken.generate!` directly.
    transient do
      plaintext { SecureRandom.urlsafe_base64(32) }
    end

    token_digest       { ApiToken.digest(plaintext) }
    last_token_preview { plaintext.last(4) }
  end
end
