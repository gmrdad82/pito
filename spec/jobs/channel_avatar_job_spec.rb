# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelAvatarJob do
  let(:channel) { create(:channel) }

  it "delegates to Channel::Avatar::Ingest with the channel + source URL" do
    ingest = instance_double(Channel::Avatar::Ingest, call: nil)
    expect(Channel::Avatar::Ingest)
      .to receive(:new).with(channel:, source_url: "https://yt3.ggpht.com/x").and_return(ingest)

    described_class.new.perform(channel.id, "https://yt3.ggpht.com/x")
  end

  it "no-ops when the channel is gone" do
    expect(Channel::Avatar::Ingest).not_to receive(:new)
    expect { described_class.new.perform(0, "https://yt3.ggpht.com/x") }.not_to raise_error
  end
end
