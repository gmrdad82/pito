# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoThumbnailJob do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel:) }

  it "delegates to Video::Thumbnail::Ingest with the video + source URL" do
    ingest = instance_double(Video::Thumbnail::Ingest, call: nil)
    expect(Video::Thumbnail::Ingest)
      .to receive(:new).with(video:, source_url: "https://i.ytimg.com/x.jpg").and_return(ingest)

    described_class.new.perform(video.id, "https://i.ytimg.com/x.jpg")
  end

  it "no-ops when the video is gone" do
    expect(Video::Thumbnail::Ingest).not_to receive(:new)
    expect { described_class.new.perform(0, "https://i.ytimg.com/x.jpg") }.not_to raise_error
  end
end
