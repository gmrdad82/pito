# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::Visit do
  let!(:channel) { create(:channel, handle: "@gaming", youtube_channel_id: "UCtest") }

  describe ".call" do
    subject(:payload) { described_class.call(channel) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes body with channel visit HTML" do
      expect(payload["body"]).to be_present
    end

    it "is NOT follow-up-able (no reply_handle — never user-facing)" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "carries anchor: true so the event_<id> DOM anchor is rendered" do
      expect(payload["anchor"]).to be true
    end

    it "carries reply_target for FollowUpDispatchJob routing" do
      expect(payload["reply_target"]).to eq("channel_visit")
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end

    it "carries the channel_id for the consume endpoint" do
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "defaults to the visiting state" do
      expect(payload["visit_state"]).to eq("visiting")
    end
  end

  describe ".call with a conversation (visiting)" do
    let(:conversation) { Conversation.singleton }

    subject(:payload) { described_class.call(channel, conversation: conversation) }

    it "is NOT follow-up-able (no reply_handle — internal machine flow)" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "carries reply_target for FollowUpDispatchJob routing" do
      expect(payload["reply_target"]).to eq("channel_visit")
    end

    it "carries anchor: true so the event_<id> DOM anchor is rendered" do
      expect(payload["anchor"]).to be true
    end
  end

  describe ".call with state: :visited" do
    subject(:payload) { described_class.call(channel, state: :visited) }

    it "marks visit_state visited" do
      expect(payload["visit_state"]).to eq("visited")
    end

    it "renders the consumed copy with no shimmer but a manual link" do
      expect(payload["body"]).not_to include("pito-network-shimmer")
      expect(payload["body"]).to include("youtube.com")
    end
  end

  describe ".call with destination: :channel (default)" do
    subject(:payload) { described_class.call(channel) }

    it "stamps visit_destination as 'channel'" do
      expect(payload["visit_destination"]).to eq("channel")
    end

    it "renders the YouTube channel URL in the body" do
      expect(payload["body"]).to include("www.youtube.com/@gaming")
    end
  end

  describe ".call with destination: :studio" do
    subject(:payload) { described_class.call(channel, destination: :studio) }

    it "stamps visit_destination as 'studio'" do
      expect(payload["visit_destination"]).to eq("studio")
    end

    it "renders the Studio URL in the body" do
      expect(payload["body"]).to include("studio.youtube.com/channel/UCtest")
    end

    it "does NOT render the regular YouTube channel URL" do
      expect(payload["body"]).not_to include("www.youtube.com/@gaming")
    end
  end
end
