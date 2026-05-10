require "rails_helper"

RSpec.describe NotificationDeliveryChannel::Slack do
  let(:webhook_url) { "https://hooks.slack.com/services/abc/def" }
  let(:channel) { described_class.new }
  let(:notification) { create(:notification) }

  before do
    AppSetting.delete_all
    AppSetting.create!(key: "max_panes", value: "5", slack_enabled: true)
    allow(Rails.application.credentials)
      .to receive(:dig)
      .with(:notifications, :slack_webhook_url)
      .and_return(webhook_url)
  end

  describe "#enabled?" do
    it "delegates to AppSetting.slack_delivery_enabled?" do
      expect(channel.enabled?).to be(true)
      AppSetting.first.update!(slack_enabled: false)
      expect(channel.enabled?).to be(false)
    end
  end

  describe "#webhook_url" do
    it "reads from credentials" do
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
    it "skips when AppSetting flag false" do
      AppSetting.first.update!(slack_enabled: false)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "skips when webhook URL is missing" do
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
end
