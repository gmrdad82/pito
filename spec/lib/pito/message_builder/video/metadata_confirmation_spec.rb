# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::MetadataConfirmation do
  let(:conversation) { create(:conversation) }
  let!(:channel)     { create(:channel) }
  let(:video)        { create(:video, channel: channel, title: "Speed Run Gold") }

  describe ".call" do
    subject(:payload) { described_class.call(video, field: field, value: value, conversation: conversation) }

    context "with a description field" do
      let(:field) { "description" }
      let(:value) { "A brand new description." }

      it "returns a Hash" do
        expect(payload).to be_a(Hash)
      end

      it "has command of video_metadata" do
        expect(payload["command"]).to eq("video_metadata")
      end

      it "has html false" do
        expect(payload["html"]).to be false
      end

      it "includes the video title in body" do
        expect(payload["body"]).to include("Speed Run Gold")
      end

      it "stamps video_id in the payload" do
        expect(payload["video_id"]).to eq(video.id)
      end

      it "stamps video_title in the payload" do
        expect(payload["video_title"]).to eq(video.title)
      end

      it "stamps field in the payload" do
        expect(payload["field"]).to eq("description")
      end

      it "stamps staged_value in the payload" do
        expect(payload["staged_value"]).to eq(value)
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

    context "with a tags field (Array value)" do
      let(:field) { "tags" }
      let(:value) { %w[speedrun retro gold] }

      it "passes the Array through as staged_value" do
        expect(payload["staged_value"]).to eq(value)
        expect(payload["staged_value"]).to be_an(Array)
      end

      it "joins the tags preview with a comma-space in body" do
        expect(payload["body"]).to include("speedrun, retro, gold")
      end
    end

    context "with a description longer than the preview limit" do
      let(:field) { "description" }
      let(:value) { "x" * 150 }

      it "truncates the preview in body to 120 chars plus an ellipsis" do
        expect(payload["body"]).to include("#{'x' * 120}…")
      end

      it "does not include the untruncated full value in body" do
        expect(payload["body"]).not_to include("x" * 121)
      end
    end

    context "with a description at or under the preview limit" do
      let(:field) { "description" }
      let(:value) { "x" * 120 }

      it "does not append an ellipsis" do
        expect(payload["body"]).not_to include("…")
      end
    end
  end
end
