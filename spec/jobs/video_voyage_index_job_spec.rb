# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoVoyageIndexJob do
  let(:video) { create(:video, title: "Lies of P guide", description: "Bosses", category_id: "20") }

  it "is a no-op when the video is missing" do
    expect(Video::VoyageIndexer).not_to receive(:call)
    described_class.new.perform(0)
  end

  it "embeds the video via Video::VoyageIndexer" do
    expect(Video::VoyageIndexer).to receive(:call).with(video)
    described_class.new.perform(video.id)
  end
end
