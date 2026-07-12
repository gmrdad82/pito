# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::Detail, type: :service do
  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel,
           title:              "Alpha Cast",
           handle:             "@alpha",
           youtube_channel_id: "UCabc")
  end

  describe ".call" do
    subject(:payload) { described_class.call(channel, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html: true" do
      expect(payload["html"]).to be true
    end

    it "includes a non-empty body" do
      expect(payload["body"]).to be_present
    end

    it "stamps channel_id in the payload" do
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "is follow-up-able (reply_target and reply_handle are set)" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
    end

    it "sets reply_target to 'channel_detail'" do
      expect(payload["reply_target"]).to eq("channel_detail")
    end

    it "sets a non-blank reply_handle" do
      expect(payload["reply_handle"]).to be_present
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end

  describe ".call without conversation (nil)" do
    subject(:payload) { described_class.call(channel, conversation: nil) }

    it "returns a Hash with a body" do
      expect(payload["body"]).to be_present
    end

    it "is NOT follow-up-able when conversation is nil" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "still stamps channel_id" do
      expect(payload["channel_id"]).to eq(channel.id)
    end
  end
end
