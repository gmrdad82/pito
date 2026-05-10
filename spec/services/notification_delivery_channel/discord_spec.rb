require "rails_helper"

RSpec.describe NotificationDeliveryChannel::Discord do
  let(:webhook_url) { "https://discord.com/api/webhooks/123/abc" }
  let(:channel) { described_class.new }
  let(:notification) { create(:notification) }

  before do
    AppSetting.delete_all
    AppSetting.create!(key: "max_panes", value: "5", discord_enabled: true)
    allow(Rails.application.credentials)
      .to receive(:dig)
      .with(:notifications, :discord_webhook_url)
      .and_return(webhook_url)
  end

  describe "#enabled?" do
    it "delegates to AppSetting.discord_delivery_enabled?" do
      expect(channel.enabled?).to be(true)
      AppSetting.first.update!(discord_enabled: false)
      expect(channel.enabled?).to be(false)
    end
  end

  describe "#webhook_url" do
    it "reads from credentials" do
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
    it "skips when AppSetting flag false" do
      AppSetting.first.update!(discord_enabled: false)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "skips when webhook URL is blank" do
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
end
