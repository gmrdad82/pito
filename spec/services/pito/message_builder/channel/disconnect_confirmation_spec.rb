# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::DisconnectConfirmation do
  let(:conversation) { create(:conversation) }
  let!(:channel) { create(:channel, handle: "@gaming", title: "Gaming Channel") }

  describe ".call" do
    subject(:payload) { described_class.call(channel, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has command of disconnect" do
      expect(payload["command"]).to eq("disconnect")
    end

    it "has html true" do
      expect(payload["html"]).to be true
    end

    it "includes the shimmer-wrapped handle in body" do
      expect(payload["body"]).to include("pito-token")
      expect(payload["body"]).to include("@gaming")
    end

    it "stamps channel_id in the payload" do
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "includes expand_detail as an Array" do
      expect(payload["expand_detail"]).to be_an(Array)
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
