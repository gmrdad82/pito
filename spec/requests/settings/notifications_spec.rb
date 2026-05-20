require "rails_helper"

# Beta 4 — F3-B. Unified notifications request surface.
#
# Two member actions, one per brand:
#
#   PATCH /settings/notifications/discord  ->  #update_discord
#   PATCH /settings/notifications/slack    ->  #update_slack
#
# Each preserves the tri-state save flow that lived on the prior
# per-brand controllers (blank → no-op, "clear" → wipe, else →
# validate + test-ping + save) plus the same brand-flavoured flashes.
# Booleans cross the wire as "yes"/"no" per CLAUDE.md hard rules.
RSpec.describe "Settings::Notifications", type: :request do
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:discord_legacy_url) { "https://discordapp.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }

  describe "friendly URL" do
    it "exposes /settings/notifications/discord" do
      expect(settings_notifications_discord_path).to eq("/settings/notifications/discord")
    end

    it "exposes /settings/notifications/slack" do
      expect(settings_notifications_slack_path).to eq("/settings/notifications/slack")
    end

    it "drops the legacy /settings/discord_webhook helper" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:settings_discord_webhook_path)
    end

    it "drops the legacy /settings/slack_webhook helper" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:settings_slack_webhook_path)
    end
  end

  describe "PATCH /settings/notifications/discord" do
    context "with a valid URL and a successful test ping" do
      before { stub_request(:post, discord_url).to_return(status: 204, body: "") }

      it "creates the install-level row" do
        expect {
          patch settings_notifications_discord_path,
                params: { discord_webhook_url: discord_url }
        }.to change { NotificationDeliveryChannel.where(kind: "discord").count }.by(1)
      end

      it "persists `webhook_url` + `last_validated_at`" do
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_url }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to eq(discord_url)
        expect(record.last_validated_at).to be_within(5.seconds).of(Time.current)
      end

      it "redirects back to /settings with a notice" do
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_url }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Discord updated/)
      end

      it "fires exactly one test ping with the locked copy" do
        ping_stub = stub_request(:post, discord_url)
          .with(body: { "content" => "Pito test ping — Discord webhook configured." }.to_json)
          .to_return(status: 204, body: "")
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_url }
        expect(ping_stub).to have_been_requested.once
      end

      it "accepts the legacy discordapp.com host form" do
        stub_request(:post, discord_legacy_url).to_return(status: 204, body: "")
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_legacy_url }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record).to be_present
        expect(record.webhook_url).to eq(discord_legacy_url)
      end

      it "does not touch a pre-existing Slack row" do
        slack = NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_url }
        slack.reload
        expect(slack.webhook_url).to eq(slack_url)
      end
    end

    context "with a blank URL — no-op (preserve existing URL)" do
      it "does not create a row on a fresh blank submission" do
        expect {
          patch settings_notifications_discord_path,
                params: { discord_webhook_url: "" }
        }.not_to change { NotificationDeliveryChannel.where(kind: "discord").count }
      end

      it "preserves the existing URL" do
        NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to eq(discord_url)
      end

      it "redirects with the `unchanged` flash and does not fire a ping" do
        stub = stub_request(:post, %r{discord(?:app)?\.com})
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "" }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Discord unchanged/i)
        expect(stub).not_to have_been_requested
      end

      it "treats whitespace-only as no-op" do
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "   " }
        expect(NotificationDeliveryChannel.where(kind: "discord").count).to eq(0)
        expect(flash[:notice]).to match(/Discord unchanged/i)
      end
    end

    context "with the literal `clear` keyword" do
      it "creates a row with nil URL on a fresh clear" do
        expect {
          patch settings_notifications_discord_path,
                params: { discord_webhook_url: "clear" }
        }.to change { NotificationDeliveryChannel.where(kind: "discord").count }.by(1)
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to be_nil
      end

      it "blanks an existing URL" do
        NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "clear" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to be_nil
      end

      it "redirects with the `cleared` flash (distinct from `updated`) and does not fire a ping" do
        stub = stub_request(:post, %r{discord(?:app)?\.com})
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "clear" }
        expect(flash[:notice]).to match(/Discord cleared/i)
        expect(flash[:notice]).not_to match(/updated/i)
        expect(stub).not_to have_been_requested
      end

      it "accepts case-insensitive `CLEAR`" do
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "CLEAR" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record).to be_present
        expect(record.webhook_url).to be_nil
        expect(flash[:notice]).to match(/Discord cleared/i)
      end
    end

    context "with an invalid URL" do
      it "redirects with an alert and does not save" do
        expect {
          patch settings_notifications_discord_path,
                params: { discord_webhook_url: "https://discord.com/foo" }
        }.not_to change { NotificationDeliveryChannel.count }
        expect(flash[:alert]).to match(/invalid Discord URL/i)
      end

      it "rejects a non-HTTPS URL" do
        bad = "http://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123"
        patch settings_notifications_discord_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL on the wrong host" do
        bad = "https://attacker.com/api/webhooks/123456789012345678/abc-DEF_xyz123"
        patch settings_notifications_discord_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "does not fire a test ping for an invalid URL" do
        stub = stub_request(:post, %r{discord(?:app)?\.com})
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "https://discord.com/foo" }
        expect(stub).not_to have_been_requested
      end

      it "preserves the previously-saved URL on a bad submission" do
        existing = NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: "https://discord.com/foo" }
        expect(existing.reload.webhook_url).to eq(discord_url)
      end
    end

    context "with a valid URL but a failing test ping" do
      it "does not save the row on a non-2xx response" do
        stub_request(:post, discord_url).to_return(status: 500, body: "")
        expect {
          patch settings_notifications_discord_path,
                params: { discord_webhook_url: discord_url }
        }.not_to change { NotificationDeliveryChannel.count }
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end

      it "does not save the row on a timeout" do
        stub_request(:post, discord_url).to_raise(::Net::OpenTimeout)
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_url }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end
    end
  end

  describe "PATCH /settings/notifications/slack" do
    context "with a valid URL and a successful test ping" do
      before { stub_request(:post, slack_url).to_return(status: 200, body: "ok") }

      it "creates the install-level row" do
        expect {
          patch settings_notifications_slack_path,
                params: { slack_webhook_url: slack_url }
        }.to change { NotificationDeliveryChannel.where(kind: "slack").count }.by(1)
      end

      it "persists `webhook_url` + `last_validated_at`" do
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: slack_url }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.webhook_url).to eq(slack_url)
        expect(record.last_validated_at).to be_within(5.seconds).of(Time.current)
      end

      it "redirects back with the `updated` flash" do
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: slack_url }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Slack updated/)
      end

      it "fires exactly one test ping with the locked copy" do
        ping_stub = stub_request(:post, slack_url)
          .with(body: { "text" => "Pito test ping — Slack webhook configured." }.to_json)
          .to_return(status: 200, body: "ok")
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: slack_url }
        expect(ping_stub).to have_been_requested.once
      end

      it "does not touch a pre-existing Discord row" do
        discord = NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: slack_url }
        discord.reload
        expect(discord.webhook_url).to eq(discord_url)
      end
    end

    context "with a blank URL — no-op" do
      it "preserves the existing URL on a blank submission" do
        NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: "" }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.webhook_url).to eq(slack_url)
        expect(flash[:notice]).to match(/Slack unchanged/i)
      end
    end

    context "with the literal `clear` keyword" do
      it "blanks the URL" do
        NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: "clear" }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.webhook_url).to be_nil
        expect(flash[:notice]).to match(/Slack cleared/i)
      end
    end

    context "with an invalid URL" do
      it "redirects with an alert" do
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: "https://hooks.slack.com/wrong" }
        expect(flash[:alert]).to match(/invalid Slack URL/i)
        expect(NotificationDeliveryChannel.count).to eq(0)
      end
    end

    context "with a failing test ping" do
      it "does not save on 404" do
        stub_request(:post, slack_url).to_return(status: 404, body: "")
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: slack_url }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/Slack ping failed/i)
      end
    end
  end

  describe "unauthenticated", :unauthenticated do
    it "bounces /settings/notifications/discord to /login" do
      stub_request(:post, %r{discord(?:app)?\.com})
      expect {
        patch settings_notifications_discord_path,
              params: { discord_webhook_url: discord_url }
      }.not_to change { NotificationDeliveryChannel.count }
      expect(response).to redirect_to(login_path)
    end

    it "bounces /settings/notifications/slack to /login" do
      stub_request(:post, %r{hooks\.slack\.com})
      expect {
        patch settings_notifications_slack_path,
              params: { slack_webhook_url: slack_url }
      }.not_to change { NotificationDeliveryChannel.count }
      expect(response).to redirect_to(login_path)
    end
  end
end
