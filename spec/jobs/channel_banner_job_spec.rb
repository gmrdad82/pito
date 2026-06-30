# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelBannerJob do
  let(:channel) { create(:channel) }

  it "delegates to Channel::Banner::Ingest with the channel + source URL" do
    ingest = instance_double(Channel::Banner::Ingest, call: nil)
    expect(Channel::Banner::Ingest)
      .to receive(:new).with(channel:, source_url: "https://yt3.ggpht.com/banner").and_return(ingest)

    described_class.new.perform(channel.id, "https://yt3.ggpht.com/banner")
  end

  it "no-ops when the channel is gone" do
    expect(Channel::Banner::Ingest).not_to receive(:new)
    expect { described_class.new.perform(0, "https://yt3.ggpht.com/banner") }.not_to raise_error
  end
end
