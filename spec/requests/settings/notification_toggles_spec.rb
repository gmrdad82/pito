require "rails_helper"

# Beta 4 — F3-B-SIMPLIFY-MODEL (2026-05-20). Shared notification
# routing toggles.
#
# `PATCH /settings/notification_toggles/:kind` flips a SHARED Boolean
# column on the canonical `AppSetting.singleton_row`. `:kind` maps to
# the column:
#
#   "all"          -> `notifications_send_all`
#   "daily_digest" -> `notifications_send_daily_digest`
#
# Body: `enabled=yes|no`. Checkboxes save independently of webhook
# configuration; the per-brand webhook gate decides which brands
# actually receive a delivery.
RSpec.describe "Settings::NotificationToggles", type: :request do
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }

  describe "friendly URLs" do
    it "exposes `/settings/notification_toggles/all`" do
      expect(settings_notification_toggle_path(kind: "all")).to eq("/settings/notification_toggles/all")
    end

    it "exposes `/settings/notification_toggles/daily_digest`" do
      expect(settings_notification_toggle_path(kind: "daily_digest")).to eq("/settings/notification_toggles/daily_digest")
    end

    it "rejects an unknown kind segment at the router" do
      expect {
        Rails.application.routes.recognize_path(
          "/settings/notification_toggles/banana", method: :patch
        )
      }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "PATCH /settings/notification_toggles/all" do
    it "flips `notifications_send_all` to true on the singleton" do
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(AppSetting.notifications_send_all?).to be(true)
    end

    it "flips `notifications_send_all` to false on `enabled=no`" do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "no" }
      expect(AppSetting.notifications_send_all?).to be(false)
    end

    it "does NOT touch `notifications_send_daily_digest`" do
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(AppSetting.notifications_send_daily_digest?).to be(true)
    end

    it "redirects back to /settings with a notice naming the new state" do
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to match(/all on/i)
    end

    it "does NOT touch any NotificationDeliveryChannel row" do
      slack_row = NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)
      expect {
        patch settings_notification_toggle_path(kind: "all"),
              params: { enabled: "yes" }
      }.not_to change { slack_row.reload.webhook_url }
    end
  end

  describe "PATCH /settings/notification_toggles/daily_digest" do
    it "flips `notifications_send_daily_digest` to true" do
      patch settings_notification_toggle_path(kind: "daily_digest"),
            params: { enabled: "yes" }
      expect(AppSetting.notifications_send_daily_digest?).to be(true)
    end

    it "flips `notifications_send_daily_digest` to false on `enabled=no`" do
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
      patch settings_notification_toggle_path(kind: "daily_digest"),
            params: { enabled: "no" }
      expect(AppSetting.notifications_send_daily_digest?).to be(false)
    end

    it "does NOT touch `notifications_send_all`" do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      patch settings_notification_toggle_path(kind: "daily_digest"),
            params: { enabled: "yes" }
      expect(AppSetting.notifications_send_all?).to be(true)
    end

    it "redirects with a `daily digest on` notice" do
      patch settings_notification_toggle_path(kind: "daily_digest"),
            params: { enabled: "yes" }
      expect(flash[:notice]).to match(/daily digest on/i)
    end
  end

  describe "yes/no boundary on `enabled`" do
    it "'yes' → true" do
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(AppSetting.notifications_send_all?).to be(true)
    end

    it "'no' → false" do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "no" }
      expect(AppSetting.notifications_send_all?).to be(false)
    end

    it "absent → false (`enabled` not in the params)" do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      patch settings_notification_toggle_path(kind: "all")
      expect(AppSetting.notifications_send_all?).to be(false)
    end

    it "raw Boolean strings coerce to false (not allowed by the contract)" do
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "true" }
      expect(AppSetting.notifications_send_all?).to be(false)
    end
  end

  describe "independence from webhook configuration" do
    # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The shared toggle saves
    # independently of webhook state — checkbox can be ON with no
    # webhook configured. The per-brand webhook presence is enforced
    # by the worker / dispatcher, not the toggle save.
    it "saves the toggle even with NO NotificationDeliveryChannel rows" do
      expect(NotificationDeliveryChannel.count).to eq(0)
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(response).to redirect_to(settings_path)
      expect(AppSetting.notifications_send_all?).to be(true)
    end

    it "saves the toggle even when brand rows have nil webhook_url" do
      NotificationDeliveryChannel.create!(kind: "slack", webhook_url: nil)
      NotificationDeliveryChannel.create!(kind: "discord", webhook_url: nil)
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(flash[:alert]).to be_nil
      expect(AppSetting.notifications_send_all?).to be(true)
    end
  end

  describe "unauthenticated", :unauthenticated do
    it "bounces to /login without flipping the toggle" do
      patch settings_notification_toggle_path(kind: "all"),
            params: { enabled: "yes" }
      expect(response).to redirect_to(login_path)
      expect(AppSetting.notifications_send_all?).to be(false)
    end
  end
end
