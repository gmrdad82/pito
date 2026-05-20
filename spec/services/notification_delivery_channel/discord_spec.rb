require "rails_helper"

RSpec.describe NotificationDeliveryChannel::Discord do
  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The Discord delivery gate is an
  # AND of:
  #   1. A shared toggle ON on `AppSetting.singleton_row`.
  #   2. A `NotificationDeliveryChannel` row exists for Discord with a
  #      present `webhook_url`.
  # The per-brand routing-flag columns were dropped.
  let(:webhook_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:channel) { described_class.new }
  let(:notification) { create(:notification) }

  # Configures a Discord `NotificationDeliveryChannel` row + the
  # install-level shared toggle so the delivery gate is on end-to-end.
  def configure_discord_channel(url: webhook_url, toggle_on: true)
    NotificationDeliveryChannel.find_or_initialize_by(kind: "discord").tap do |row|
      row.webhook_url = url
      row.save!(validate: false)
    end
    AppSetting.set_notification_toggle!(:notifications_send_all, toggle_on)
  end

  before do
    AppSetting.delete_all
    NotificationDeliveryChannel.delete_all
    configure_discord_channel
    # Default to nil for any credentials.dig call (e.g., the formatter
    # looking up :pito_avatar_url). The dispatcher reads the AR row
    # first for `webhook_url`, so the credentials fallback is only
    # exercised by the explicit specs below.
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    allow(Rails.application.credentials)
      .to receive(:dig)
      .with(:notifications, :discord_webhook_url)
      .and_return(webhook_url)
  end

  describe "#enabled?" do
    it "delegates to AppSetting.discord_delivery_enabled? (driven by toggle + channel row)" do
      expect(channel.enabled?).to be(true)
      # Flipping the shared toggle off disables delivery.
      AppSetting.set_notification_toggle!(:notifications_send_all, false)
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
    it "is :discord_delivered_at" do
      expect(channel.delivered_at_column).to eq(:discord_delivered_at)
    end
  end

  describe "#payload_for" do
    it "returns a payload (Spec 02 will replace this stub)" do
      payload = channel.payload_for(notification)
      expect(payload).to be_a(Hash)
      expect(payload).not_to be_empty
    end
  end

  describe "#perform_post and #deliver integration" do
    it "POSTs JSON with Content-Type application/json on success" do
      stub = stub_request(:post, webhook_url)
        .with(headers: { "Content-Type" => "application/json" })
        .to_return(status: 204, body: "")
      channel.deliver(notification)
      expect(stub).to have_been_requested
    end

    it "stamps discord_delivered_at on 204 No Content" do
      stub_request(:post, webhook_url).to_return(status: 204, body: "")
      expect { channel.deliver(notification) }
        .to change { notification.reload.discord_delivered_at }.from(nil)
    end

    it "stamps on 200 with garbage body (Discord doesn't require JSON)" do
      stub_request(:post, webhook_url).to_return(status: 200, body: "<html>")
      expect { channel.deliver(notification) }
        .to change { notification.reload.discord_delivered_at }.from(nil)
    end

    it "treats 400 Bad Request as terminal" do
      stub_request(:post, webhook_url).to_return(status: 400, body: "bad")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
      expect(notification.reload.discord_delivered_at).to be_nil
      expect(notification.reload.last_error).to include("400")
    end

    it "treats 401 Unauthorized as terminal" do
      stub_request(:post, webhook_url).to_return(status: 401, body: "")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
    end

    it "treats 404 Not Found as terminal" do
      stub_request(:post, webhook_url).to_return(status: 404, body: "")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
    end

    it "raises on 429 (transient)" do
      stub_request(:post, webhook_url).to_return(status: 429, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on 500 (transient)" do
      stub_request(:post, webhook_url).to_return(status: 500, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on 502" do
      stub_request(:post, webhook_url).to_return(status: 502, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on 503" do
      stub_request(:post, webhook_url).to_return(status: 503, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on 504" do
      stub_request(:post, webhook_url).to_return(status: 504, body: "")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
    end

    it "raises on a connection refused error" do
      stub_request(:post, webhook_url).to_raise(::Errno::ECONNREFUSED)
      expect { channel.deliver(notification) }.to raise_error(::Errno::ECONNREFUSED)
    end

    it "raises on a read timeout" do
      stub_request(:post, webhook_url).to_raise(::Net::ReadTimeout)
      expect { channel.deliver(notification) }.to raise_error(::Net::ReadTimeout)
    end
  end

  describe "skip paths" do
    it "skips when both shared toggles are off" do
      AppSetting.set_notification_toggle!(:notifications_send_all, false)
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, false)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "skips when no channel row exists and credentials carry no URL" do
      NotificationDeliveryChannel.delete_all
      allow(Rails.application.credentials)
        .to receive(:dig)
        .with(:notifications, :discord_webhook_url)
        .and_return(nil)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "skips when discord_delivered_at is already stamped" do
      notification.update!(discord_delivered_at: 1.minute.ago)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:already_delivered)
    end
  end

  describe "retry exhaustion smoke" do
    it "after 5 transient failures retry_count is at least 5 and column stays NULL" do
      stub_request(:post, webhook_url).to_return(status: 500, body: "")
      5.times do
        expect { channel.deliver(notification) }.to raise_error(StandardError)
      end
      expect(notification.reload.discord_delivered_at).to be_nil
      expect(notification.reload.retry_count).to be >= 5
      expect(notification.reload.last_error).to include("500")
    end
  end

  # F2 — timeouts MUST be set on every Net::HTTP instance so a hung
  # webhook endpoint cannot wedge the delivery worker indefinitely.
  describe "HTTP timeouts (audit F2)" do
    it "sets open / read / write / ssl timeouts on the Net::HTTP instance" do
      stub_request(:post, webhook_url).to_return(status: 204, body: "")
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

  # F3 — webhook URL must point at a Discord-owned host. A
  # misconfigured credential pointing anywhere else (attacker domain,
  # loopback, raw IP) must NOT result in a POST.
  describe "webhook host allowlist (audit F3)" do
    it "passes for a discord.com URL" do
      expect(channel.deliverable_url?("https://discord.com/api/webhooks/1/x")).to be(true)
    end

    it "passes for a discordapp.com URL" do
      expect(channel.deliverable_url?("https://discordapp.com/api/webhooks/1/x")).to be(true)
    end

    it "rejects an attacker-controlled host" do
      expect(channel.deliverable_url?("https://attacker.com/foo")).to be(false)
    end

    it "rejects a loopback address" do
      expect(channel.deliverable_url?("https://127.0.0.1/foo")).to be(false)
    end

    it "rejects an http (non-TLS) discord URL" do
      expect(channel.deliverable_url?("http://discord.com/api/webhooks/1/x")).to be(false)
    end

    it "returns false on a malformed URI" do
      expect(channel.deliverable_url?("ht!tp://[bad")).to be(false)
    end

    it "skips delivery (status :disabled) when configured URL is not allowlisted" do
      configure_discord_channel(url: "https://attacker.com/api/webhooks/1/x")
      # No HTTP stub registered — if the channel attempted a POST
      # WebMock would raise, so the assertion that the result is
      # `:skipped` doubles as proof we never sent a request.
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "logs a warning when configured URL fails the allowlist" do
      configure_discord_channel(url: "https://attacker.com/api/webhooks/1/x")
      expect(Rails.logger).to receive(:warn).with(/DISCORD_HOSTS allowlist/)
      channel.deliver(notification)
    end
  end
end
