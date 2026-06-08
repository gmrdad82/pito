# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::UnlistConfirmation do
  let(:conversation) { create(:conversation) }
  let!(:channel)     { create(:channel) }
  let(:video)        { create(:video, channel: channel, title: "Boss Fight Highlights") }

  describe ".call" do
    subject(:payload) { described_class.call(video, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has command of video_unlist" do
      expect(payload["command"]).to eq("video_unlist")
    end

    it "has html false" do
      expect(payload["html"]).to be false
    end

    it "includes the video title in body" do
      expect(payload["body"]).to include("Boss Fight Highlights")
    end

    it "stamps video_id in the payload" do
      expect(payload["video_id"]).to eq(video.id)
    end

    it "stamps video_title in the payload" do
      expect(payload["video_title"]).to eq(video.title)
    end

    it "is follow-up-able with target confirmation" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
