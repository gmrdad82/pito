# frozen_string_literal: true

require "rails_helper"

# InApp delivery channel spec. The InApp channel is a deliberate no-op:
# the Notification row's existence IS the delivery. The channel overrides
# `deliver` entirely and returns Result(:ok) without any HTTP POST or
# column stamp.
RSpec.describe Pito::Notifications::DeliveryChannel::InApp do
  subject(:channel) { described_class.new }

  before do
    # NotificationDeliveryChannel is Phase-26 — not yet in the schema.
    stub_const("NotificationDeliveryChannel",
               Class.new do
                 def self.for(kind)
                   Pito::Notifications::DeliveryChannel::Base.for(kind)
                 end
               end)
  end

  it "is always enabled" do
    expect(channel.enabled?).to be true
  end

  it "has no webhook_url" do
    expect(channel.webhook_url).to be_nil
  end

  it "has no delivered_at_column" do
    expect(channel.delivered_at_column).to be_nil
  end

  it "deliver returns Result(status: :ok) for any notification" do
    n = double("notification")
    result = channel.deliver(n)
    expect(result.status).to eq(:ok)
  end

  it "deliver never calls perform_post" do
    n = double("notification")
    expect(channel).not_to receive(:perform_post)
    channel.deliver(n)
  end

  it "deliver never calls update! on the notification" do
    n = double("notification")
    expect(n).not_to receive(:update!)
    channel.deliver(n)
  end

  it "perform_post raises NotImplementedError" do
    expect { channel.perform_post("url", {}) }
      .to raise_error(NotImplementedError)
  end
end
