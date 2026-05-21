require "rails_helper"

# A test subclass that lets specs poke each subclass-interface seam
# without going through Discord/Slack's HTTP machinery.
#
# Subclasses `Pito::Notifications::DeliveryChannel::Base` — a PORO,
# not the AR model. `NotificationDeliveryChannel` is the AR model;
# `Pito::Notifications::DeliveryChannel::Base` is the PORO dispatcher.
class TestNotificationChannel < Pito::Notifications::DeliveryChannel::Base
  attr_accessor :enabled_value, :webhook_url_value, :delivered_at_column_value,
                :payload_value, :stub_response, :raise_on_post

  def initialize
    @enabled_value = true
    @webhook_url_value = "https://example.test/webhook"
    @delivered_at_column_value = :discord_delivered_at
    @payload_value = { "content" => "test" }
    @stub_response = nil
    @raise_on_post = nil
  end

  def enabled?
    @enabled_value
  end

  def webhook_url
    @webhook_url_value
  end

  def delivered_at_column
    @delivered_at_column_value
  end

  def payload_for(_notification)
    @payload_value
  end

  def perform_post(_url, _payload)
    raise @raise_on_post if @raise_on_post
    @stub_response
  end
end

# Bare-bones HTTP response double so specs don't need real Net::HTTP
# round-trips.
StubResponse = Struct.new(:code, :body) do
  def to_s
    body
  end
end unless defined?(StubResponse)

RSpec.describe Pito::Notifications::DeliveryChannel do
  let(:notification) { create(:notification) }

  describe ".for (via NotificationDeliveryChannel AR model facade)" do
    it "returns Discord for 'discord'" do
      expect(NotificationDeliveryChannel.for("discord")).to be_a(Pito::Notifications::DeliveryChannel::Discord)
    end

    it "returns Slack for 'slack'" do
      expect(NotificationDeliveryChannel.for("slack")).to be_a(Pito::Notifications::DeliveryChannel::Slack)
    end

    it "returns InApp for 'in_app'" do
      expect(NotificationDeliveryChannel.for("in_app")).to be_a(Pito::Notifications::DeliveryChannel::InApp)
    end

    it "raises ArgumentError for unknown kinds" do
      expect { NotificationDeliveryChannel.for("email") }.to raise_error(ArgumentError, /unknown channel/)
    end

    it "accepts a symbol" do
      expect(NotificationDeliveryChannel.for(:discord)).to be_a(Pito::Notifications::DeliveryChannel::Discord)
    end
  end

  describe "#deliver" do
    let(:channel) { TestNotificationChannel.new }

    it "short-circuits with :disabled when enabled? is false" do
      channel.enabled_value = false
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "short-circuits with :already_delivered when the column is stamped" do
      notification.update!(discord_delivered_at: 1.minute.ago)
      result = channel.deliver(notification)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:already_delivered)
    end

    it "calls payload_for and perform_post on the happy path" do
      channel.stub_response = StubResponse.new("204", "")
      expect(channel).to receive(:payload_for).with(notification).and_call_original
      channel.deliver(notification)
    end

    it "stamps the column on 2xx" do
      channel.stub_response = StubResponse.new("200", "ok")
      expect { channel.deliver(notification) }
        .to change { notification.reload.discord_delivered_at }.from(nil)
    end

    it "clears last_error on 2xx" do
      notification.update!(last_error: "old", retry_count: 1)
      channel.stub_response = StubResponse.new("204", "")
      channel.deliver(notification)
      expect(notification.reload.last_error).to be_nil
    end

    it "raises a transient StandardError on 5xx so Sidekiq retries" do
      channel.stub_response = StubResponse.new("500", "server error")
      expect { channel.deliver(notification) }.to raise_error(StandardError, /500/)
    end

    it "records last_error and bumps retry_count on 5xx" do
      channel.stub_response = StubResponse.new("502", "bad gateway")
      expect { channel.deliver(notification) }.to raise_error(StandardError)
      expect(notification.reload.retry_count).to eq(1)
      expect(notification.reload.last_error).to include("502")
    end

    it "raises on a network error and records the failure" do
      channel.raise_on_post = ::Errno::ECONNREFUSED.new
      expect { channel.deliver(notification) }.to raise_error(::Errno::ECONNREFUSED)
      expect(notification.reload.retry_count).to eq(1)
      expect(notification.reload.last_error).to be_present
    end

    it "does NOT raise on 4xx (non-429) — terminal failure" do
      channel.stub_response = StubResponse.new("400", "bad request")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
      expect(result.reason).to eq(:terminal)
      expect(notification.reload.discord_delivered_at).to be_nil
      expect(notification.reload.last_error).to include("400")
    end

    it "does NOT raise on 401 (terminal)" do
      channel.stub_response = StubResponse.new("401", "unauthorized")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
    end

    it "does NOT raise on 404 (terminal)" do
      channel.stub_response = StubResponse.new("404", "not found")
      result = channel.deliver(notification)
      expect(result.status).to eq(:failed)
    end

    it "raises on 429 (transient — Sidekiq retries)" do
      channel.stub_response = StubResponse.new("429", "rate limited")
      expect { channel.deliver(notification) }.to raise_error(StandardError, /rate/)
      expect(notification.reload.retry_count).to eq(1)
    end
  end
end
