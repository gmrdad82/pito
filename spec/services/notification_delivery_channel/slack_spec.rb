require "rails_helper"

RSpec.describe NotificationDeliveryChannel::Slack do
  # Phase 29 — Unit A1. The Slack delivery gate
  # (`AppSetting.slack_delivery_enabled?`) is now derived from the
  # `NotificationDeliveryChannel` row for the kind — its existence plus
  # a present `webhook_url` and at least one routing flag set. The
  # orphaned `AppSetting.slack_enabled` column was dropped. The
  # dispatcher's `webhook_url` still reads the AR row first, then the
  # `credentials.notifications.slack_webhook_url` fallback.
  let(:webhook_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:channel) { described_class.new }
  let(:notification) { create(:notification) }

  # Configures a Slack `NotificationDeliveryChannel` row so the
  # delivery gate is on. `everything: true` is the routing-flag the
  # gate looks for.
  def configure_slack_channel(url: webhook_url, everything: true)
    NotificationDeliveryChannel.find_or_initialize_by(kind: "slack").tap do |row|
      row.webhook_url = url
      row.everything = everything
      row.save!(validate: false)
    end
  end

  before do
    AppSetting.delete_all
    NotificationDeliveryChannel.delete_all
    configure_slack_channel
    # Default to nil for any credentials.dig call (e.g., the formatter
    # looking up :pito_avatar_url). The dispatcher reads the AR row
    # first for `webhook_url`, so the credentials fallback is only
    # exercised by the explicit specs below.
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    allow(Rails.application.credentials)
      .to receive(:dig)
      .with(:notifications, :slack_webhook_url)
      .and_return(webhook_url)
  end

  describe "#enabled?" do
    it "delegates to AppSetting.slack_delivery_enabled? (driven by the channel row)" do
      expect(channel.enabled?).to be(true)
      # Dropping the routing flag flips the gate off.
      NotificationDeliveryChannel.slack.update_columns(everything: false, daily_digest: false)
      expect(channel.enabled?).to be(false)
    end

    it "is false when no NotificationDeliveryChannel row exists" do
      NotificationDeliveryChannel.delete_all
      expect(channel.enabled?).to be(false)
    end
  end

  describe "#webhook_url" do
    it "reads the NotificationDeliveryChannel row first" do
      expect(channel.webhook_url).to eq(webhook_url)
    end

    it "falls back to credentials when no channel row exists" do
      NotificationDeliveryChannel.delete_all
      expect(channel.webhook_url).to eq(webhook_url)
    end
  end

  describe "#delivered_at_column" do
    it "is :slack_delivered_at" do
      expect(channel.delivered_at_column).to eq(:slack_delivered_at)
    end
  end

  describe "#perform_post and #deliver integration" do
    it "POSTs JSON with Content-Type application/json" do
      stub = stub_request(:post, webhook_url)
        .with(headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: "ok")
      channel.deliver(notification)
      expect(stub).to have_been_requested
    end

    it "stamps slack_delivered_at on 200" do
      stub_request(:post, webhook_url).to_return(status: 200, body: "ok")
      expect { channel.deliver(notification) }
        .to change { notification.reload.slack_delivered_at }.from(nil)
    end

    it "treats 400 as terminal" do
      stub_request(:post, webhook_url).to_return(status: 400, body: "bad")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
    end

    it "treats 404 as terminal" do
      stub_request(:post, webhook_url).to_return(status: 404, body: "")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
    end

    it "raises on 429" do
      stub_request(:post, webhook_url).to_return(status: 429, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on 500" do
      stub_request(:post, webhook_url).to_return(status: 500, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on a network error" do
      stub_request(:post, webhook_url).to_raise(::Net::OpenTimeout)
      expect { channel.deliver(notification) }.to raise_error(::Net::OpenTimeout)
    end
  end

  describe "skip paths" do
    it "skips when the channel row has no routing flag set" do
      NotificationDeliveryChannel.slack.update_columns(everything: false, daily_digest: false)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "skips when no channel row exists and credentials carry no URL" do
      NotificationDeliveryChannel.delete_all
      allow(Rails.application.credentials)
        .to receive(:dig).with(:notifications, :slack_webhook_url).and_return(nil)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "skips when slack_delivered_at is already stamped" do
      notification.update!(slack_delivered_at: 1.minute.ago)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:already_delivered)
    end
  end

  # F2 — verify HTTP timeouts apply identically through the shared
  # `configure_http` helper.
  describe "HTTP timeouts (audit F2)" do
    it "sets open / read / write / ssl timeouts on the Net::HTTP instance" do
      stub_request(:post, webhook_url).to_return(status: 200, body: "ok")
      captured = nil
      original_new = Net::HTTP.method(:new)
      allow(Net::HTTP).to receive(:new) do |*args|
        captured = original_new.call(*args)
        captured
      end
      channel.deliver(notification)
      expect(captured.open_timeout).to eq(5)
      expect(captured.read_timeout).to eq(10)
      expect(captured.write_timeout).to eq(10)
      expect(captured.ssl_timeout).to eq(5)
    end
  end

  # F3 — webhook URL must point at hooks.slack.com.
  describe "webhook host allowlist (audit F3)" do
    it "passes for a hooks.slack.com URL" do
      expect(channel.deliverable_url?("https://hooks.slack.com/services/T/B/x")).to be(true)
    end

    it "rejects an attacker-controlled host" do
      expect(channel.deliverable_url?("https://attacker.com/foo")).to be(false)
    end

    it "rejects loopback" do
      expect(channel.deliverable_url?("https://127.0.0.1/foo")).to be(false)
    end

    it "rejects slack.com (only the webhooks subdomain is trusted)" do
      expect(channel.deliverable_url?("https://slack.com/api/foo")).to be(false)
    end

    it "rejects an http (non-TLS) slack URL" do
      expect(channel.deliverable_url?("http://hooks.slack.com/services/T/B/x")).to be(false)
    end

    it "returns false on a malformed URI" do
      expect(channel.deliverable_url?("ht!tp://[bad")).to be(false)
    end

    it "skips delivery (status :disabled) when configured URL is not allowlisted" do
      configure_slack_channel(url: "https://attacker.com/services/T/B/x")
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "logs a warning when configured URL fails the allowlist" do
      configure_slack_channel(url: "https://attacker.com/services/T/B/x")
      expect(Rails.logger).to receive(:warn).with(/SLACK_HOSTS allowlist/)
      channel.deliver(notification)
    end
  end
end
