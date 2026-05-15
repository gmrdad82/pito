require "rails_helper"

# Phase 26 — 01b. Slack webhook pane request surface.
#
# `PATCH /settings/slack_webhook` validates the URL regex, fires a
# test ping via `Webhooks::SlackClient`, and only persists the row
# when the ping returns 2xx. Booleans cross the wire as "yes"/"no"
# per CLAUDE.md hard rules.
#
# Phase 29 — Unit A2. The signed-in user is always TOTP-configured
# (mandatory-2FA gate), so the `RecentTotpVerification` concern on the
# Slack webhook write demands a fresh `totp_code` on every PATCH. The
# `before` re-pins the auto-signed-in user with the known seed and
# resets the replay-defense watermark; every gated PATCH carries
# `totp_code: valid_code`.
RSpec.describe "Settings::SlackWebhooks", type: :request do
  let(:valid_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:seed)       { "JBSWY3DPEHPK3PXP" }
  let(:valid_code) { ROTP::TOTP.new(seed).now }

  before do |example|
    next if example.metadata[:unauthenticated]

    user = User.first
    user.update!(
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago,
      totp_disabled_at: nil
    )
    user.update_columns(totp_last_used_step: nil)
    sign_in_as(user)
  end

  describe "PATCH /settings/slack_webhook" do
    context "with a valid URL and a successful test ping" do
      before do
        stub_request(:post, valid_url).to_return(status: 200, body: "ok")
      end

      it "creates the install-level row" do
        expect {
          patch settings_slack_webhook_path,
                params: { slack_webhook_url: valid_url, everything: "yes", daily_digest: "no",
                          totp_code: valid_code }
        }.to change { NotificationDeliveryChannel.where(kind: "slack").count }.by(1)
      end

      it "persists `webhook_url`, `everything`, `daily_digest`, `last_validated_at`" do
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, everything: "yes", daily_digest: "yes",
                        totp_code: valid_code }

        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.webhook_url).to eq(valid_url)
        expect(record.everything).to be(true)
        expect(record.daily_digest).to be(true)
        expect(record.last_validated_at).to be_within(5.seconds).of(Time.current)
      end

      it "redirects back to /settings with a notice" do
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, everything: "yes", daily_digest: "no",
                        totp_code: valid_code }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Slack webhook saved/)
      end

      it "fires exactly one test ping with the locked copy" do
        ping_stub = stub_request(:post, valid_url)
          .with(body: { "text" => "Pito test ping — Slack webhook configured." }.to_json)
          .to_return(status: 200, body: "ok")
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, everything: "no", daily_digest: "no",
                        totp_code: valid_code }
        expect(ping_stub).to have_been_requested.once
      end

      it "updates the existing row on a second save (no second row)" do
        NotificationDeliveryChannel.create!(
          kind: "slack", webhook_url: valid_url,
          everything: false, daily_digest: false
        )
        expect {
          patch settings_slack_webhook_path,
                params: { slack_webhook_url: valid_url, everything: "yes", daily_digest: "yes",
                          totp_code: valid_code }
        }.not_to change { NotificationDeliveryChannel.where(kind: "slack").count }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.everything).to be(true)
        expect(record.daily_digest).to be(true)
      end

      it "stores `everything`/`daily_digest` as false when the form omits them" do
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, totp_code: valid_code }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "stores `everything`/`daily_digest` as false on 'no' strings" do
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, everything: "no", daily_digest: "no",
                        totp_code: valid_code }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "rejects raw Boolean wire values (true/false) as 'no'" do
        # Yes/no boundary — only the strings "yes"/"no" are valid. Anything
        # else (including the Boolean strings) coerces to false.
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url, everything: "true", daily_digest: "1",
                        totp_code: valid_code }
        record = NotificationDeliveryChannel.find_by(kind: "slack")
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end
    end

    context "with an invalid URL" do
      it "redirects with an alert and does not save" do
        expect {
          patch settings_slack_webhook_path,
                params: { slack_webhook_url: "https://hooks.slack.com/foo", totp_code: valid_code }
        }.not_to change { NotificationDeliveryChannel.count }

        expect(response).to redirect_to(settings_path)
        expect(flash[:alert]).to match(/invalid Slack webhook URL/i)
      end

      it "does not fire a test ping" do
        stub = stub_request(:post, %r{hooks\.slack\.com})
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: "https://hooks.slack.com/foo", totp_code: valid_code }
        expect(stub).not_to have_been_requested
      end

      it "rejects a non-HTTPS URL" do
        bad = "http://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
        patch settings_slack_webhook_path, params: { slack_webhook_url: bad, totp_code: valid_code }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL on the wrong host" do
        bad = "https://attacker.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
        patch settings_slack_webhook_path, params: { slack_webhook_url: bad, totp_code: valid_code }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects an empty URL" do
        patch settings_slack_webhook_path, params: { slack_webhook_url: "", totp_code: valid_code }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL with surrounding whitespace via strip" do
        # The controller strips whitespace before matching the regex, so
        # a URL surrounded by spaces but otherwise valid IS accepted.
        # This is the inverse case — internal whitespace breaks the
        # regex.
        bad = valid_url + " extra"
        patch settings_slack_webhook_path, params: { slack_webhook_url: bad, totp_code: valid_code }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "preserves the previously-saved URL on a bad submission" do
        existing = NotificationDeliveryChannel.create!(
          kind: "slack", webhook_url: valid_url,
          everything: false, daily_digest: false
        )
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: "https://hooks.slack.com/foo", totp_code: valid_code }
        expect(existing.reload.webhook_url).to eq(valid_url)
      end
    end

    context "with a valid URL but a failing test ping" do
      it "does not save the row on a 404 response" do
        stub_request(:post, valid_url).to_return(status: 404, body: "")
        expect {
          patch settings_slack_webhook_path,
                params: { slack_webhook_url: valid_url, totp_code: valid_code }
        }.not_to change { NotificationDeliveryChannel.count }
        expect(flash[:alert]).to match(/Slack test ping failed/i)
        expect(flash[:alert]).to include("404")
      end

      it "does not save the row on a 500 response" do
        stub_request(:post, valid_url).to_return(status: 500, body: "")
        patch settings_slack_webhook_path, params: { slack_webhook_url: valid_url, totp_code: valid_code }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to include("500")
      end

      it "does not save the row on a timeout" do
        stub_request(:post, valid_url).to_raise(::Net::OpenTimeout)
        patch settings_slack_webhook_path, params: { slack_webhook_url: valid_url, totp_code: valid_code }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/timeout/i)
      end

      it "does not save the row on a DNS failure" do
        stub_request(:post, valid_url).to_raise(SocketError.new("nope"))
        patch settings_slack_webhook_path, params: { slack_webhook_url: valid_url, totp_code: valid_code }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/DNS/i)
      end

      it "preserves the previously-saved row" do
        existing = NotificationDeliveryChannel.create!(
          kind: "slack", webhook_url: valid_url,
          everything: true, daily_digest: true
        )
        new_url = "https://hooks.slack.com/services/T99XYZW/B88UVWX/zZyYxXwW1234567"
        stub_request(:post, new_url).to_return(status: 500, body: "")
        patch settings_slack_webhook_path, params: { slack_webhook_url: new_url, totp_code: valid_code }
        expect(existing.reload.webhook_url).to eq(valid_url)
        expect(existing.reload.everything).to be(true)
      end
    end
  end

  describe "unauthenticated", :unauthenticated do
    it "bounces to /login without touching anything" do
      stub_request(:post, %r{hooks\.slack\.com}) # safety — should never fire.
      expect {
        patch settings_slack_webhook_path,
              params: { slack_webhook_url: valid_url }
      }.not_to change { NotificationDeliveryChannel.count }
      expect(response).to redirect_to(login_path)
    end
  end

  describe "friendly URL" do
    it "preserves /settings/slack_webhook" do
      expect(settings_slack_webhook_path).to eq("/settings/slack_webhook")
    end
  end

  describe "yes/no boundary on `everything`" do
    before { stub_request(:post, valid_url).to_return(status: 200, body: "ok") }

    it "'yes' → true" do
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, everything: "yes", totp_code: valid_code }
      expect(NotificationDeliveryChannel.slack.everything).to be(true)
    end

    it "'no' → false" do
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, everything: "no", totp_code: valid_code }
      expect(NotificationDeliveryChannel.slack.everything).to be(false)
    end

    it "absent → false" do
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, totp_code: valid_code }
      expect(NotificationDeliveryChannel.slack.everything).to be(false)
    end
  end

  describe "yes/no boundary on `daily_digest`" do
    before { stub_request(:post, valid_url).to_return(status: 200, body: "ok") }

    it "'yes' → true" do
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, daily_digest: "yes", totp_code: valid_code }
      expect(NotificationDeliveryChannel.slack.daily_digest).to be(true)
    end

    it "'no' → false" do
      patch settings_slack_webhook_path,
            params: { slack_webhook_url: valid_url, daily_digest: "no", totp_code: valid_code }
      expect(NotificationDeliveryChannel.slack.daily_digest).to be(false)
    end
  end
end
