# frozen_string_literal: true

require "rails_helper"

# Discord delivery channel spec. Uses WebMock for HTTP; stubs AppSetting and
# NotificationDeliveryChannel (the Phase-26 AR model) which don't exist yet
# in the current schema. `verify_partial_doubles = true` is on globally, so
# we define the aspirational AppSetting methods before stubbing them.
RSpec.describe Pito::Notifications::DeliveryChannel::Discord do
  subject(:channel) { described_class.new }

  DISCORD_URL = "https://discord.com/api/webhooks/999/tok".freeze

  around do |example|
    old_val = ENV.fetch("PITO_DISCORD_WEBHOOK_URL", :missing)
    example.run
    old_val == :missing ? ENV.delete("PITO_DISCORD_WEBHOOK_URL") : ENV["PITO_DISCORD_WEBHOOK_URL"] = old_val
  end

  before do
    # AppSetting.discord_delivery_enabled? belongs to the Phase-26 schema.
    # Define it speculatively so partial-double verification passes.
    unless AppSetting.respond_to?(:discord_delivery_enabled?)
      AppSetting.define_singleton_method(:discord_delivery_enabled?) { true }
    end
    allow(AppSetting).to receive(:discord_delivery_enabled?).and_return(true)

    # NotificationDeliveryChannel (Phase-26 AR model) is not yet migrated.
    stub_const("NotificationDeliveryChannel",
               Class.new do
                 def self.discord; nil; end
                 def self.for(kind)
                   Pito::Notifications::DeliveryChannel::Base.for(kind)
                 end
               end)
  end

  def with_env(key, val)
    ENV[key] = val
    yield
  ensure
    ENV.delete(key)
  end

  def notification_double(delivered_at: nil, retry_count: 0)
    n = double("notification",
               title:                    "game released today",
               event_type:               "game_release_today",
               severity:                 "info",
               fires_at:                 Time.current,
               retry_count:              retry_count,
               source_calendar_entry_id: nil,
               id:                       1)
    allow(n).to receive(:read_attribute).with(:discord_delivered_at).and_return(delivered_at)
    allow(n).to receive(:update!).and_return(true)
    allow(n).to receive(:event_payload).and_return({})
    allow(n).to receive(:read?).and_return(false)
    n
  end

  # ------------------------------------------------------------------
  # webhook_url resolution
  # ------------------------------------------------------------------
  describe "#webhook_url" do
    it "falls back to ENV var when no AR row" do
      ENV["PITO_DISCORD_WEBHOOK_URL"] = DISCORD_URL
      expect(channel.webhook_url).to eq(DISCORD_URL)
    end

    it "returns nil when neither AR row nor ENV var" do
      ENV.delete("PITO_DISCORD_WEBHOOK_URL")
      expect(channel.webhook_url).to be_nil
    end
  end

  # ------------------------------------------------------------------
  # deliverable_url?
  # ------------------------------------------------------------------
  describe "#deliverable_url?" do
    it "accepts discord.com HTTPS URLs" do
      expect(channel.deliverable_url?("https://discord.com/api/webhooks/1/x")).to be true
    end

    it "accepts discordapp.com HTTPS URLs" do
      expect(channel.deliverable_url?("https://discordapp.com/api/webhooks/1/x")).to be true
    end

    it "rejects HTTP (non-HTTPS)" do
      expect(channel.deliverable_url?("http://discord.com/api/webhooks/1/x")).to be false
    end

    it "rejects non-Discord hosts" do
      expect(channel.deliverable_url?("https://evil.com/hook")).to be false
    end

    it "rejects garbage strings" do
      expect(channel.deliverable_url?("not a url")).to be false
    end
  end

  # ------------------------------------------------------------------
  # enabled?
  # ------------------------------------------------------------------
  describe "#enabled?" do
    context "when delivery is globally disabled" do
      before { allow(AppSetting).to receive(:discord_delivery_enabled?).and_return(false) }

      it "returns false" do
        expect(channel.enabled?).to be false
      end
    end

    context "when webhook_url is blank" do
      before { ENV.delete("PITO_DISCORD_WEBHOOK_URL") }

      it "returns false" do
        expect(channel.enabled?).to be false
      end
    end

    context "when webhook_url is a valid Discord URL" do
      before { ENV["PITO_DISCORD_WEBHOOK_URL"] = DISCORD_URL }

      it "returns true" do
        expect(channel.enabled?).to be true
      end
    end

    context "when webhook_url points at a non-Discord host" do
      before { ENV["PITO_DISCORD_WEBHOOK_URL"] = "https://evil.com/hook" }

      it "returns false (host allowlist rejection)" do
        expect(channel.enabled?).to be false
      end
    end
  end

  # ------------------------------------------------------------------
  # HTTP delivery (WebMock)
  # ------------------------------------------------------------------
  describe "#deliver HTTP paths" do
    before do
      ENV["PITO_DISCORD_WEBHOOK_URL"] = DISCORD_URL
    end

    it "2xx → stamps discord_delivered_at and returns :ok" do
      stub_request(:post, DISCORD_URL).to_return(status: 200)
      n = notification_double
      expect(n).to receive(:update!).with(
        discord_delivered_at: instance_of(ActiveSupport::TimeWithZone),
        last_error: nil
      )
      result = channel.deliver(n)
      expect(result.status).to eq(:ok)
    end

    it "404 → terminal failure, no retry raised" do
      stub_request(:post, DISCORD_URL).to_return(status: 404, body: "not found")
      n = notification_double(retry_count: 0)
      expect(n).to receive(:update!).with(hash_including(last_error: /404/, retry_count: 1))
      result = channel.deliver(n)
      expect(result.status).to eq(:failed)
      expect(result.reason).to eq(:terminal)
    end

    it "429 → records failure + raises TransientFailure" do
      stub_request(:post, DISCORD_URL).to_return(status: 429, body: "rate limited")
      n = notification_double(retry_count: 1)
      expect(n).to receive(:update!).with(hash_including(retry_count: 2))
      expect { channel.deliver(n) }.to raise_error(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure
      )
    end

    it "5xx → records failure + raises TransientFailure" do
      stub_request(:post, DISCORD_URL).to_return(status: 503)
      n = notification_double(retry_count: 0)
      expect(n).to receive(:update!).with(hash_including(retry_count: 1))
      expect { channel.deliver(n) }.to raise_error(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure
      )
    end

    it "connection refused → records failure + re-raises" do
      stub_request(:post, DISCORD_URL).to_raise(Errno::ECONNREFUSED)
      n = notification_double(retry_count: 0)
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
      allow(AppSetting).to receive(:discord_delivery_enabled?).and_return(false)
      n = notification_double
      result = channel.deliver(n)
      expect(result.status).to eq(:skipped)
    end
  end
end
