# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::Visit do
  let!(:video) { create(:video, title: "My Vid", youtube_video_id: "UCtest") }

  describe ".call" do
    subject(:payload) { described_class.call(video) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes body with video visit HTML" do
      expect(payload["body"]).to be_present
    end

    it "is NOT follow-up-able (no reply_handle — never user-facing)" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "carries anchor: true so the event_<id> DOM anchor is rendered" do
      expect(payload["anchor"]).to be true
    end

    it "carries reply_target for FollowUpDispatchJob routing" do
      expect(payload["reply_target"]).to eq("video_visit")
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end

    it "carries the video_id for the consume endpoint" do
      expect(payload["video_id"]).to eq(video.id)
    end

    it "defaults to the visiting state" do
      expect(payload["visit_state"]).to eq("visiting")
    end
  end

  describe ".call with a conversation (visiting)" do
    let(:conversation) { Conversation.singleton }

    subject(:payload) { described_class.call(video, conversation: conversation) }

    it "is NOT follow-up-able (no reply_handle — internal machine flow)" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "carries reply_target for FollowUpDispatchJob routing" do
      expect(payload["reply_target"]).to eq("video_visit")
    end

    it "carries anchor: true so the event_<id> DOM anchor is rendered" do
      expect(payload["anchor"]).to be true
    end
  end

  describe ".call with state: :visited" do
    subject(:payload) { described_class.call(video, state: :visited) }

    it "marks visit_state visited" do
      expect(payload["visit_state"]).to eq("visited")
    end

    it "renders the consumed copy with no shimmer but a manual link" do
      expect(payload["body"]).not_to include("pito-network-shimmer")
      expect(payload["body"]).to include("youtube.com")
    end
  end

  describe ".call with destination: :youtube (default)" do
    subject(:payload) { described_class.call(video) }

    it "stamps visit_destination as 'youtube'" do
      expect(payload["visit_destination"]).to eq("youtube")
    end

    it "renders the YouTube watch-page URL in the body" do
      expect(payload["body"]).to include("www.youtube.com/watch?v=UCtest")
    end
  end

  describe ".call with destination: :studio" do
    subject(:payload) { described_class.call(video, destination: :studio) }

    it "stamps visit_destination as 'studio'" do
      expect(payload["visit_destination"]).to eq("studio")
    end

    it "renders the Studio URL in the body" do
      expect(payload["body"]).to include("studio.youtube.com/video/UCtest/edit")
    end

    it "does NOT render the regular YouTube watch-page URL" do
      expect(payload["body"]).not_to include("www.youtube.com/watch?v=UCtest")
    end
  end
end
