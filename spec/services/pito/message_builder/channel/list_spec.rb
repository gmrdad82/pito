# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::List do
  let(:conversation) { create(:conversation) }
  let!(:alpha) { create(:channel, title: "Alpha Tube", handle: "@alpha", youtube_channel_id: "UCa") }
  let!(:beta)  { create(:channel, title: "Beta Cast", handle: "@beta", youtube_channel_id: "UCb") }

  describe ".call" do
    let(:channels) { ::Channel.order(:title) }

    subject(:payload) { described_class.call(channels, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes channel titles in body" do
      expect(payload["body"]).to include("Alpha Tube")
      expect(payload["body"]).to include("Beta Cast")
    end

    it "includes channel handles in body" do
      expect(payload["body"]).to include("@alpha")
      expect(payload["body"]).to include("@beta")
    end

    it "wraps the intro count in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">2</span>})
    end

    it "wraps the channels noun in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">channels</span>})
    end

    context "when there is exactly 1 channel" do
      let(:channels) { ::Channel.where(id: alpha.id) }

      it "uses the singular noun 'channel'" do
        expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">channel</span>})
      end

      it "does not use the plural noun 'channels'" do
        expect(payload["body"]).not_to match(%r{<span class="pito-subject-shimmer[^"]*">channels</span>})
      end
    end

    it "is follow-up-able with target channel_list" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("channel_list")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
