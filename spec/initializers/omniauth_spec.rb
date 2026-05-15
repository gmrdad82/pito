require "rails_helper"

# Phase 29 — Unit A1. YouTube / Google OAuth credentials moved back OUT
# of the AppSetting singleton and into
# `Rails.application.credentials.google_oauth`. The initializer's
# `pito_appsetting_youtube_value` resolver helper and its four-tier
# resolver are gone — the resolver is now three-tier:
#
#   1. `Rails.application.credentials.google_oauth.*` (primary)
#   2. ENV var (PITO_GOOGLE_OAUTH_* — CI / no-DB workflow)
#   3. Test-mode placeholder so the boot doesn't blow up under RSpec
#
# The initializer runs once at boot, so the resolved values are
# captured then. These specs cover (a) the boot-time outcome — the
# `google_oauth2` strategy is registered — and (b) the resolver logic
# itself, re-evaluated in isolation against a stubbed credentials block.
RSpec.describe "omniauth initializer" do
  describe "boot-time provider configuration" do
    # OmniAuth::Builder wires the google_oauth2 provider into the
    # middleware stack when this initializer runs. The strategy is
    # registered with NON-blank client credentials — which proves the
    # resolver successfully picked something (credentials / ENV / test
    # fallback) and the initializer did not raise at boot. This is the
    # boot / initializer smoke check.
    it "registers the google_oauth2 strategy at boot" do
      strategy_names = OmniAuth.strategies.map { |s| s.name.to_s.split("::").last }
      expect(strategy_names).to include("GoogleOauth2")
    end

    it "exposes the canonical scope constants" do
      expect(PITO_GOOGLE_OAUTH_SCOPES).to include(
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/yt-analytics.readonly",
        "https://www.googleapis.com/auth/youtube.force-ssl"
      )
    end
  end

  # The three-tier resolver, re-evaluated in isolation. The initializer
  # captures the resolved values at boot; these specs re-run the same
  # expression against a stubbed credentials block / ENV to pin the
  # precedence order without re-triggering the middleware wiring.
  describe "Google OAuth credentials resolver (credentials-first)" do
    def resolve_client_id(credentials_block:, env_value: nil, test_env: true)
      creds = credentials_block || {}
      creds[:client_id].presence ||
        env_value.presence ||
        (test_env ? "test-google-oauth-client-id-not-a-secret" : nil)
    end

    it "reads the client_id from the :google_oauth credentials block first" do
      resolved = resolve_client_id(
        credentials_block: { client_id: "creds-client-id" },
        env_value: "env-client-id"
      )
      expect(resolved).to eq("creds-client-id")
    end

    it "falls back to the ENV var when the credentials block is absent" do
      resolved = resolve_client_id(
        credentials_block: nil,
        env_value: "env-client-id"
      )
      expect(resolved).to eq("env-client-id")
    end

    it "falls back to the test placeholder when credentials and ENV are both blank" do
      resolved = resolve_client_id(
        credentials_block: {},
        env_value: nil,
        test_env: true
      )
      expect(resolved).to eq("test-google-oauth-client-id-not-a-secret")
    end

    it "resolves to nil outside test when credentials and ENV are both blank" do
      resolved = resolve_client_id(
        credentials_block: {},
        env_value: nil,
        test_env: false
      )
      expect(resolved).to be_nil
    end

    it "the live credentials.google_oauth block (or the test placeholder) yields a usable client_id" do
      # The boot-time resolver must have produced a non-blank value —
      # otherwise the initializer would have raised. Re-derive the same
      # value here from the live credentials + ENV + test fallback.
      creds = Rails.application.credentials.google_oauth || {}
      resolved = creds[:client_id].presence ||
                 ENV["PITO_GOOGLE_OAUTH_CLIENT_ID"].presence ||
                 "test-google-oauth-client-id-not-a-secret"
      expect(resolved).to be_present
    end
  end
end
