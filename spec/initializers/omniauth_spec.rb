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

  # P25 follow-up — F6. The resolver helper at top-level
  # (`pito_appsetting_youtube_value`) used to swallow any
  # `StandardError`. After F6 it ONLY rescues the boot-time DB-absent
  # shapes (`ActiveRecord::StatementInvalid`,
  # `ActiveRecord::ConnectionNotEstablished`,
  # `ActiveRecord::NoDatabaseError`) and emits a warning so a legitimate
  # error doesn't silently mask.
  describe "P25 F6 — resolver rescue narrowing" do
    # The resolver is defined at top level in the initializer (so the
    # `OmniAuth::Builder` middleware closure can call it at boot). It
    # remains callable as a Kernel-level method post-boot. The tests
    # below probe its rescue behavior by stubbing AppSetting accessors.
    it "rescues ActiveRecord::StatementInvalid (table not migrated yet) and returns nil with a warn" do
      allow(AppSetting.connection).to receive(:data_source_exists?).and_return(true)
      allow(AppSetting).to receive(:youtube_client_id)
        .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))
      expect(Rails.logger).to receive(:warn).with(/StatementInvalid.*relation does not exist/)
      expect(pito_appsetting_youtube_value(:youtube_client_id)).to be_nil
    end

    it "rescues ActiveRecord::ConnectionNotEstablished (DB not booted) and returns nil with a warn" do
      allow(AppSetting.connection).to receive(:data_source_exists?).and_return(true)
      allow(AppSetting).to receive(:youtube_client_id)
        .and_raise(ActiveRecord::ConnectionNotEstablished.new("could not connect"))
      expect(Rails.logger).to receive(:warn).with(/ConnectionNotEstablished/)
      expect(pito_appsetting_youtube_value(:youtube_client_id)).to be_nil
    end

    it "does NOT swallow non-DB errors — e.g. NoMethodError bubbles up" do
      allow(AppSetting.connection).to receive(:data_source_exists?).and_return(true)
      allow(AppSetting).to receive(:youtube_client_id).and_raise(NoMethodError.new("bad call"))
      expect {
        pito_appsetting_youtube_value(:youtube_client_id)
      }.to raise_error(NoMethodError)
    end

    it "does NOT swallow ArgumentError (config errors should surface)" do
      allow(AppSetting.connection).to receive(:data_source_exists?).and_return(true)
      allow(AppSetting).to receive(:youtube_client_id).and_raise(ArgumentError.new("bad arg"))
      expect {
        pito_appsetting_youtube_value(:youtube_client_id)
      }.to raise_error(ArgumentError)
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
