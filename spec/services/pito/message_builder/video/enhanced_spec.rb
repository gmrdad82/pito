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

    it "has no html key (plain typewriter body)" do
      expect(payload).not_to have_key("html")
    end
  end
end
