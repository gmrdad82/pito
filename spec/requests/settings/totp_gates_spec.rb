require "rails_helper"

# 2026-05-11 — Fresh-TOTP gate covers sensitive write actions when
# the signed-in user has 2FA on. The gate is implemented in
# `RecentTotpVerification` and is wired into:
#
#   * `Settings::UserController#update` — user username / password edit.
#   * `SettingsController#update` for `section=voyage` — the Voyage
#     project-notes flag write.
#   * `Settings::SlackWebhooksController#update` — Slack webhook URL save.
#   * `Settings::DiscordWebhooksController#update` — Discord webhook URL save.
#
# Failure copy is intentionally generic — `credentials don't match.`
# — so the response never leaks whether the password / code / both
# was the failing field.
#
# Phase 29 — Unit A2. With the mandatory-2FA gate
# (`Sessions::AuthConcern#require_totp_configured!`), an authenticated
# user is ALWAYS TOTP-configured — a TOTP-off authenticated user is
# bounced to the enrollment page before any gated write runs. The
# "2FA off" scenarios that used to live here are therefore replaced
# with assertions that the mandatory gate redirects to
# `/settings/security/totp`.
#
# Read-only viewing of `/settings` is NOT gated; only writes.
RSpec.describe "2FA gates on sensitive Settings writes", type: :request do
  let(:password) { "supersecret123" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }
  let(:user) do
    User.first || create(:user, password: password, password_confirmation: password)
  end
  let(:valid_code) { ROTP::TOTP.new(seed).now }

  before do
    user.update!(
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
    # Reset the replay-defense watermark so each verify within the
    # same describe block runs against a clean slate.
    user.update_columns(totp_last_used_step: nil, totp_disabled_at: nil)
    sign_in_as(user)
  end

  # ---- Settings::User#update ----
  describe "PATCH /settings/user (user account edit)" do
    let(:new_username) { "edit_#{SecureRandom.hex(4)}" }
    let(:base_user_params) do
      {
        username: new_username,
        current_password: password,
        password: "",
        password_confirmation: ""
      }
    end

    it "rejects with a generic flash when the totp_code is missing" do
      original_username = user.username
      patch settings_user_path, params: { user: base_user_params }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("credentials don").and include("match")
      expect(user.reload.username).to eq(original_username)
    end

    it "rejects when the totp_code is wrong" do
      original_username = user.username
      patch settings_user_path, params: { user: base_user_params, totp_code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("credentials don").and include("match")
      expect(user.reload.username).to eq(original_username)
    end

    it "proceeds when the totp_code is correct" do
      patch settings_user_path,
            params: { user: base_user_params, totp_code: valid_code }
      expect(response).to redirect_to(settings_path)
      expect(user.reload.username).to eq(new_username)
    end

    # 2026-05-11 polish (Fix 4) — the inline `name="totp_code"` field
    # was retired; the layout-level TOTP modal injects it on submit.
    it "renders the form with the totp-modal controller wired when 2FA is on" do
      get settings_user_path
      expect(response.body).to include('data-controller="totp-modal"')
      expect(response.body).to include('data-totp-modal-required-value="yes"')
      expect(response.body).not_to include('id="totp_code"')
    end
  end

  # ---- SettingsController#update_voyage ----
  describe "PATCH /settings (section=voyage)" do
    let(:voyage_params) do
      {
        section: "voyage",
        settings: { voyage_index_project_notes: "yes" }
      }
    end

    it "redirects with a generic alert when the totp_code is missing" do
      patch settings_path, params: voyage_params
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("credentials don").and include("match")
      expect(AppSetting.voyage_indexing_project_notes?).to be false
    end

    it "redirects with a generic alert when the totp_code is wrong" do
      patch settings_path, params: voyage_params.merge(totp_code: "000000")
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("credentials don").and include("match")
      expect(AppSetting.voyage_indexing_project_notes?).to be false
    end

    it "proceeds when the totp_code is correct" do
      patch settings_path, params: voyage_params.merge(totp_code: valid_code)
      expect(response).to redirect_to(settings_path)
      expect(AppSetting.voyage_indexing_project_notes?).to be true
    end
  end

  # ---- Settings::SlackWebhooksController#update ----
  describe "PATCH /settings/slack_webhook" do
    let(:valid_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }

    it "redirects with a generic alert when the totp_code is missing" do
      stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      expect {
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, everything: "yes", daily_digest: "no" }
      }.not_to change { NotificationDeliveryChannel.where(kind: "slack").count }

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("credentials don").and include("match")
    end

    it "redirects with a generic alert when the totp_code is wrong" do
      stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, totp_code: "000000" }
      expect(NotificationDeliveryChannel.where(kind: "slack").count).to eq(0)
      follow_redirect!
      expect(response.body).to include("credentials don").and include("match")
    end

    it "proceeds when the totp_code is correct" do
      stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, totp_code: valid_code }
      expect(NotificationDeliveryChannel.where(kind: "slack").count).to eq(1)
      expect(NotificationDeliveryChannel.find_by(kind: "slack").webhook_url).to eq(valid_url)
    end
  end

  # ---- Settings::DiscordWebhooksController#update ----
  describe "PATCH /settings/discord_webhook" do
    let(:valid_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }

    it "redirects with a generic alert when the totp_code is missing" do
      stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      expect {
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "yes", daily_digest: "no" }
      }.not_to change { NotificationDeliveryChannel.where(kind: "discord").count }

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("credentials don").and include("match")
    end

    it "redirects with a generic alert when the totp_code is wrong" do
      stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      patch settings_discord_webhook_path,
            params: { discord_webhook_url: valid_url, totp_code: "000000" }
      expect(NotificationDeliveryChannel.where(kind: "discord").count).to eq(0)
      follow_redirect!
      expect(response.body).to include("credentials don").and include("match")
    end

    it "proceeds when the totp_code is correct" do
      stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      patch settings_discord_webhook_path,
            params: { discord_webhook_url: valid_url, totp_code: valid_code }
      expect(NotificationDeliveryChannel.where(kind: "discord").count).to eq(1)
      expect(NotificationDeliveryChannel.find_by(kind: "discord").webhook_url).to eq(valid_url)
    end
  end

  # ---- Mandatory-2FA gate: a TOTP-off authenticated user never reaches
  #      a gated write — they are bounced to the enrollment page. ----
  describe "with 2FA off the mandatory gate fires first" do
    before { user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil) }

    it "redirects the Voyage flag write to the TOTP enrollment page" do
      patch settings_path, params: {
        section: "voyage",
        settings: { voyage_index_project_notes: "yes" }
      }
      expect(response).to redirect_to(settings_security_totp_path)
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end

    it "redirects the user edit to the TOTP enrollment page" do
      patch settings_user_path, params: {
        user: {
          username: "no_2fa_#{SecureRandom.hex(4)}",
          current_password: password,
          password: "",
          password_confirmation: ""
        }
      }
      expect(response).to redirect_to(settings_security_totp_path)
    end

    it "redirects GET /settings to the TOTP enrollment page" do
      get settings_path
      expect(response).to redirect_to(settings_security_totp_path)
    end
  end

  # ---- Index page (read-only) renders for a TOTP-configured user. ----
  describe "GET /settings (read-only, 2FA configured)" do
    it "renders for the authenticated TOTP-configured user" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end
  end
end
