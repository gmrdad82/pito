# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::MassScheduleConfirmation do
  let(:conversation) { create(:conversation) }
  let!(:channel)      { create(:channel) }
  let(:video1)        { create(:video, channel: channel, title: "Dungeon Clear") }
  let(:video2)        { create(:video, channel: channel, title: "Boss Rush") }
  let(:time1)         { 10.days.from_now.change(usec: 0) }
  let(:time2)         { 3.days.from_now.change(usec: 0) }

  # Deliberately passed OUT of chronological order — the builder is
  # responsible for sorting ascending by publish_at, regardless of caller order.
  let(:items) do
    [
      { video: video1, publish_at: time1 },
      { video: video2, publish_at: time2 }
    ]
  end

  describe ".call" do
    subject(:payload) { described_class.call(items, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has command video_schedule_mass" do
      expect(payload["command"]).to eq("video_schedule_mass")
    end

    it "has html false" do
      expect(payload["html"]).to be false
    end

    it "includes the batch count in body" do
      expect(payload["body"]).to include("2")
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

    describe "items — sorted ascending by publish_at" do
      it "orders video2 (earlier) before video1 (later)" do
        ids = payload["items"].map { |i| i["video_id"] }
        expect(ids).to eq([ video2.id, video1.id ])
      end

      it "carries video_id, video_title, and publish_at (UTC ISO8601) per item" do
        row = payload["items"].first
        expect(row["video_id"]).to eq(video2.id)
        expect(row["video_title"]).to eq("Boss Rush")
        expect(row["publish_at"]).to eq(time2.utc.iso8601)
      end

      it "the second row is video1 with its own publish_at" do
        row = payload["items"].second
        expect(row["video_id"]).to eq(video1.id)
        expect(row["video_title"]).to eq("Dungeon Clear")
        expect(row["publish_at"]).to eq(time1.utc.iso8601)
      end
    end

    describe "expand_detail — one readable line per item, sorted ascending" do
      it "the first line names video2 (earlier) with its id and local stamp" do
        line = payload["expand_detail"].first
        expect(line).to include("##{video2.id}")
        expect(line).to include("Boss Rush")
        expect(line).to include(Pito::Formatter::SyncStamp.call(time2))
      end

      it "the second line names video1 (later)" do
        line = payload["expand_detail"].second
        expect(line).to include("##{video1.id}")
        expect(line).to include("Dungeon Clear")
        expect(line).to include(Pito::Formatter::SyncStamp.call(time1))
      end

      it "carries exactly one line per item" do
        expect(payload["expand_detail"].size).to eq(2)
      end
    end
  end
end
