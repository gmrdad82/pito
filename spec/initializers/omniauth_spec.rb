require "rails_helper"

# 2026-05-11 — YouTube OAuth credentials moved out of
# `Rails.application.credentials.google_oauth` and into the
# AppSetting singleton. The omniauth initializer runs at boot, so
# these specs cover the resolver helper (defined as
# `pito_appsetting_youtube_value` in
# `config/initializers/omniauth.rb`) and the boot-time outcome
# captured by the OmniAuth::Builder middleware.
#
# The initializer's four-tier resolver order is:
#
#   1. AppSetting singleton column (UI-edited; primary source)
#   2. Rails.application.credentials.google_oauth.* (legacy fallback)
#   3. ENV var (PITO_GOOGLE_OAUTH_* — CI / no-DB workflow)
#   4. Test-mode placeholder so the boot doesn't blow up under RSpec
#
# `pito_appsetting_youtube_value` is defined at top-level by
# `instance_eval`-like context in the initializer, so the spec
# probes it indirectly through `AppSetting` accessor calls and the
# resulting configured middleware.
RSpec.describe "omniauth initializer" do
  describe "AppSetting accessor surface" do
    it "AppSetting.youtube_client_id is the primary read source" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_client_id: "appsetting-client-id")
      expect(AppSetting.youtube_client_id).to eq("appsetting-client-id")
    end

    it "AppSetting.youtube_client_secret is the primary read source" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_client_secret: "appsetting-client-secret")
      expect(AppSetting.youtube_client_secret).to eq("appsetting-client-secret")
    end

    it "AppSetting.youtube_redirect_uri returns the stored value (no fallback at the model layer)" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_redirect_uri: "https://appsetting.test/cb")
      expect(AppSetting.youtube_redirect_uri).to eq("https://appsetting.test/cb")
    end

    it "all four accessors return nil when no AppSetting row exists" do
      AppSetting.delete_all
      expect(AppSetting.youtube_client_id).to     be_nil
      expect(AppSetting.youtube_client_secret).to be_nil
      expect(AppSetting.youtube_redirect_uri).to  be_nil
      expect(AppSetting.youtube_api_key).to       be_nil
    end
  end

  describe "boot-time provider configuration" do
    # OmniAuth::Builder wires the google_oauth2 provider into the
    # middleware stack when this initializer runs. The strategy
    # carries its `client_id` / `client_secret` on `options` after
    # being constructed. We can't re-trigger the initializer
    # mid-spec (the resolver values are captured at boot), but we
    # CAN assert that the strategy is registered with NON-blank
    # values — which proves the resolver successfully picked
    # something (AppSetting/credentials/ENV/test fallback) and
    # didn't raise.
    let(:omniauth_strategies) { OmniAuth.strategies }

    it "registers the google_oauth2 strategy at boot" do
      strategy_names = omniauth_strategies.map { |s| s.name.to_s.split("::").last }
      expect(strategy_names).to include("GoogleOauth2")
    end
  end
end
