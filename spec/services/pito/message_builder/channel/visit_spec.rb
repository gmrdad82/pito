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

    it "is NOT follow-up-able" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
