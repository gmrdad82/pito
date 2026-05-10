require "rails_helper"

RSpec.describe NotificationDeliveryChannel::InApp do
  let(:channel) { described_class.new }
  let(:notification) { create(:notification) }

  it "is always enabled" do
    expect(channel.enabled?).to be(true)
  end

  it "deliver returns :ok synchronously without HTTP" do
    expect_any_instance_of(::Net::HTTP).not_to receive(:request)
    result = channel.deliver(notification)
    expect(result.status).to eq(:ok)
  end

  it "does NOT mutate the row" do
    original = notification.attributes
    channel.deliver(notification)
    expect(notification.reload.attributes).to eq(original)
  end

  it "raises on perform_post (it should never be called)" do
    expect { channel.perform_post("u", {}) }.to raise_error(NotImplementedError)
  end
end
