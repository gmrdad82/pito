# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::Enhanced do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel: channel, title: "My Gaming Highlights") }

  describe ".call" do
    subject(:payload) { described_class.call(video) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has a body key" do
      expect(payload).to have_key("body")
    end

    it "body contains the video title" do
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "is an HTML payload (the Enhanced slot always renders HTML)" do
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to include("pito-video-enhanced-message")
    end
  end
end
