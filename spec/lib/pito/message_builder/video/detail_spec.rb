# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::Detail do
  let(:conversation) { create(:conversation) }
  let(:channel)      { create(:channel) }
  let(:video)        { create(:video, channel: channel, title: "Test Video") }

  describe ".call" do
    subject(:payload) { described_class.call(video, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes the video title in body" do
      expect(payload["body"]).to include("Test Video")
    end

    it "includes the rendered card HTML in body" do
      expect(payload["body"]).to include("pito-video-detail")
    end

    it "is follow-up-able" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
    end

    it "has reply_target of video_detail" do
      expect(payload["reply_target"]).to eq("video_detail")
    end

    it "includes the witty intro with the video title in body" do
      expect(payload["body"]).to include("Test Video")
      # Intro now lives inside the card's left column, with a timestamp slot.
      expect(payload["body"]).to include("pito-video-detail__intro")
      expect(payload["body"]).to include("data-pito-ts-slot")
    end

    it "wraps the title subject in a pito-subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">Test Video</span>})
    end

    it "escapes HTML-special characters in the title (no XSS)" do
      video.update!(title: "<b>x</b>")
      expect(payload["body"]).to include("&lt;b&gt;x&lt;/b&gt;")
      expect(payload["body"]).not_to include("<b>x</b>")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "stamps video_id in the payload" do
      expect(payload["video_id"]).to eq(video.id)
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
