# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../support/notification_double"

# Tests for DeliveryChannel::Base in isolation via a concrete subclass.
# We do NOT use the real AR Notification columns (event_payload, delivered_at,
# etc.) — the rich schema belongs to the aspirational Phase-26 migration.
# Instead we use NotificationDouble + instance_double for AR column reads.
RSpec.describe Pito::Notifications::DeliveryChannel::Base do
  # Minimal concrete subclass that POST-stubs cleanly.
  let(:webhook) { "https://discord.com/api/webhooks/123/abc" }

  let(:concrete_class) do
    Class.new(described_class) do
      def enabled?           = true
      def webhook_url        = "https://discord.com/api/webhooks/123/abc"
      def delivered_at_column = :discord_delivered_at
      def payload_for(_)     = { "content" => "test" }
      def deliverable_url?(_) = true

      def perform_post(url, payload)
        @_last_post = { url: url, payload: payload }
        @_stubbed_response
      end

      attr_accessor :_stubbed_response, :_last_post
    end
  end

  let(:channel) { concrete_class.new }

  # Notification-like double that responds to the columns Base touches.
  def notification_double(delivered_at: nil, retry_count: 0)
    n = double("notification")
    allow(n).to receive(:read_attribute).with(:discord_delivered_at).and_return(delivered_at)
    allow(n).to receive(:retry_count).and_return(retry_count)
    allow(n).to receive(:update!).and_return(true)
    n
  end

  def stub_response(code, body: "")
    r = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    channel._stubbed_response = r
    r
  end

  describe ".for" do
    it "returns a Discord instance for 'discord'" do
      expect(described_class.for("discord")).to be_a(Pito::Notifications::DeliveryChannel::Discord)
    end

    it "returns a Slack instance for 'slack'" do
      expect(described_class.for("slack")).to be_a(Pito::Notifications::DeliveryChannel::Slack)
    end

    it "returns an InApp instance for 'in_app'" do
      expect(described_class.for("in_app")).to be_a(Pito::Notifications::DeliveryChannel::InApp)
    end

    it "raises ArgumentError for unknown kinds" do
      expect { described_class.for("fax") }.to raise_error(ArgumentError, /unknown channel/)
    end
  end

  describe "#deliver — skipped paths" do
    it "returns :skipped/:disabled when enabled? is false" do
      allow(channel).to receive(:enabled?).and_return(false)
      result = channel.deliver(notification_double)
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:disabled)
    end

    it "returns :skipped/:already_delivered when column is already set" do
      result = channel.deliver(notification_double(delivered_at: Time.current))
      expect(result.status).to eq(:skipped)
      expect(result.reason).to eq(:already_delivered)
    end
  end

  describe "#deliver — 2xx success" do
    it "stamps delivered_at_column and clears last_error" do
      n = notification_double
      stub_response(200)
      expect(n).to receive(:update!).with(
        discord_delivered_at: instance_of(ActiveSupport::TimeWithZone),
        last_error: nil
      )
      result = channel.deliver(n)
      expect(result.status).to eq(:ok)
    end
  end

  describe "#deliver — 429 (rate limited)" do
    it "records failure and raises TransientFailure" do
      n = notification_double(retry_count: 2)
      stub_response(429, body: "rate limited")
      expect(n).to receive(:update!).with(
        last_error: /429/,
        retry_count: 3
      )
      expect { channel.deliver(n) }.to raise_error(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure,
        "rate limited"
      )
    end
  end

  describe "#deliver — 5xx (transient)" do
    it "records failure and raises TransientFailure" do
      n = notification_double(retry_count: 0)
      stub_response(503)
      expect(n).to receive(:update!).with(hash_including(last_error: /503/, retry_count: 1))
      expect { channel.deliver(n) }.to raise_error(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure
      )
    end
  end

  describe "#deliver — 4xx terminal (not 429)" do
    it "records failure and returns :failed/:terminal without raising" do
      n = notification_double(retry_count: 1)
      stub_response(404, body: "not found")
      expect(n).to receive(:update!).with(hash_including(last_error: /404/, retry_count: 2))
      result = channel.deliver(n)
      expect(result.status).to eq(:failed)
      expect(result.reason).to eq(:terminal)
    end
  end

  describe "#deliver — network error (StandardError from perform_post)" do
    it "records failure and re-raises" do
      n = notification_double(retry_count: 0)
      allow(channel).to receive(:perform_post).and_raise(Errno::ECONNREFUSED, "connection refused")
      expect(n).to receive(:update!).with(hash_including(retry_count: 1))
      expect { channel.deliver(n) }.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
