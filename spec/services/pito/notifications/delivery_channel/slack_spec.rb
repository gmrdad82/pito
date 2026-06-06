# frozen_string_literal: true

require "rails_helper"

# Slack delivery channel spec. Mirrors the Discord spec structure.
# AppSetting.slack_delivery_enabled? and NotificationDeliveryChannel are
# Phase-26 aspirational — defined/stubbed speculatively.
RSpec.describe Pito::Notifications::DeliveryChannel::Slack do
  subject(:channel) { described_class.new }

  SLACK_URL = "https://hooks.slack.com/services/T00/B00/tok".freeze

  around do |example|
    old_val = ENV.fetch("PITO_SLACK_WEBHOOK_URL", :missing)
    example.run
    old_val == :missing ? ENV.delete("PITO_SLACK_WEBHOOK_URL") : ENV["PITO_SLACK_WEBHOOK_URL"] = old_val
  end

  before do
    unless AppSetting.respond_to?(:slack_delivery_enabled?)
      AppSetting.define_singleton_method(:slack_delivery_enabled?) { true }
    end
    allow(AppSetting).to receive(:slack_delivery_enabled?).and_return(true)

    stub_const("NotificationDeliveryChannel",
               Class.new do
                 def self.slack; nil; end
                 def self.for(kind)
                   Pito::Notifications::DeliveryChannel::Base.for(kind)
                 end
               end)
  end

  def notification_double(delivered_at: nil, retry_count: 0)
    n = double("notification",
               title:                    "milestone reached",
               event_type:               "milestone_reached",
               severity:                 "success",
               fires_at:                 Time.current,
               retry_count:              retry_count,
               source_calendar_entry_id: nil,
               id:                       1)
    allow(n).to receive(:read_attribute).with(:slack_delivered_at).and_return(delivered_at)
    allow(n).to receive(:update!).and_return(true)
    allow(n).to receive(:event_payload).and_return({})
    allow(n).to receive(:read?).and_return(false)
    n
  end

  describe "#webhook_url" do
    it "falls back to ENV var when no AR row" do
      ENV["PITO_SLACK_WEBHOOK_URL"] = SLACK_URL
      expect(channel.webhook_url).to eq(SLACK_URL)
    end

    it "returns nil when neither AR row nor ENV var" do
      ENV.delete("PITO_SLACK_WEBHOOK_URL")
      expect(channel.webhook_url).to be_nil
    end
  end

  describe "#deliverable_url?" do
    it "accepts hooks.slack.com HTTPS URLs" do
      expect(channel.deliverable_url?(SLACK_URL)).to be true
    end

    it "rejects HTTP" do
      expect(channel.deliverable_url?("http://hooks.slack.com/services/T/B/x")).to be false
    end

    it "rejects non-Slack hosts" do
      expect(channel.deliverable_url?("https://evil.com/hook")).to be false
    end
  end

  describe "#enabled?" do
    context "when delivery is globally disabled" do
      before { allow(AppSetting).to receive(:slack_delivery_enabled?).and_return(false) }

      it "returns false" do
        expect(channel.enabled?).to be false
      end
    end

    context "when webhook_url is blank" do
      before { ENV.delete("PITO_SLACK_WEBHOOK_URL") }

      it "returns false" do
        expect(channel.enabled?).to be false
      end
    end

    context "when webhook_url is a valid Slack URL" do
      before { ENV["PITO_SLACK_WEBHOOK_URL"] = SLACK_URL }

      it "returns true" do
        expect(channel.enabled?).to be true
      end
    end

    context "when webhook_url points at a non-Slack host" do
      before { ENV["PITO_SLACK_WEBHOOK_URL"] = "https://evil.com/hook" }

      it "returns false" do
        expect(channel.enabled?).to be false
      end
    end
  end

  describe "#deliver HTTP paths" do
    before { ENV["PITO_SLACK_WEBHOOK_URL"] = SLACK_URL }

    it "2xx → stamps slack_delivered_at and returns :ok" do
      stub_request(:post, SLACK_URL).to_return(status: 200)
      n = notification_double
      expect(n).to receive(:update!).with(
        slack_delivered_at: instance_of(ActiveSupport::TimeWithZone),
        last_error: nil
      )
      result = channel.deliver(n)
      expect(result.status).to eq(:ok)
    end

    it "404 → terminal failure returned without raise" do
      stub_request(:post, SLACK_URL).to_return(status: 404, body: "not found")
      n = notification_double(retry_count: 0)
      expect(n).to receive(:update!).with(hash_including(last_error: /404/, retry_count: 1))
      result = channel.deliver(n)
      expect(result.status).to eq(:failed)
      expect(result.reason).to eq(:terminal)
    end

    it "429 → records failure + raises TransientFailure" do
      stub_request(:post, SLACK_URL).to_return(status: 429)
      n = notification_double(retry_count: 0)
      expect(n).to receive(:update!).with(hash_including(retry_count: 1))
      expect { channel.deliver(n) }.to raise_error(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure
      )
    end

    it "5xx → records failure + raises TransientFailure" do
      stub_request(:post, SLACK_URL).to_return(status: 500)
      n = notification_double
      expect(n).to receive(:update!).with(hash_including(retry_count: 1))
      expect { channel.deliver(n) }.to raise_error(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure
      )
    end

    it "connection refused → records failure + re-raises" do
      stub_request(:post, SLACK_URL).to_raise(Errno::ECONNREFUSED)
      n = notification_double
      expect(n).to receive(:update!).with(hash_including(retry_count: 1))
      expect { channel.deliver(n) }.to raise_error(Errno::ECONNREFUSED)
    end

    it "skips when already delivered" do
      n = notification_double(delivered_at: 1.hour.ago)
      expect(channel).not_to receive(:perform_post)
      result = channel.deliver(n)
      expect(result.status).to eq(:skipped)
    end

    it "skips when globally disabled" do
      allow(AppSetting).to receive(:slack_delivery_enabled?).and_return(false)
      n = notification_double
      result = channel.deliver(n)
      expect(result.status).to eq(:skipped)
    end
  end
end
