# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::ScheduleConfirmation do
  let(:conversation) { create(:conversation) }
  let!(:channel)     { create(:channel) }
  let(:video)        { create(:video, channel: channel, title: "Dungeon Clear") }
  let(:publish_time) { 7.days.from_now.utc }

  describe ".call" do
    subject(:payload) { described_class.call(video, conversation: conversation, when: publish_time) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has command of video_schedule" do
      expect(payload["command"]).to eq("video_schedule")
    end

    it "has html false" do
      expect(payload["html"]).to be false
    end

    it "includes the video title in body" do
      expect(payload["body"]).to include("Dungeon Clear")
    end

    it "includes the formatted when in body (DD-MM-YYYY local format)" do
      local_time = publish_time.in_time_zone(Time.zone)
      expect(payload["body"]).to include(local_time.strftime("%d-%m-%Y"))
    end

    it "stamps video_id in the payload" do
      expect(payload["video_id"]).to eq(video.id)
    end

    it "stamps video_title in the payload" do
      expect(payload["video_title"]).to eq(video.title)
    end

    it "stamps publish_at as ISO8601 string" do
      expect(payload["publish_at"]).to eq(publish_time.utc.iso8601)
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
