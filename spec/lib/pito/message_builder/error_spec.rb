# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Error do
  describe ".call" do
    it "returns a Hash with message_key" do
      payload = described_class.call(message_key: "pito.chat.show.needs_ref")
      expect(payload).to be_a(Hash)
      expect(payload["message_key"]).to eq("pito.chat.show.needs_ref")
    end

    it "defaults message_args to empty hash" do
      payload = described_class.call(message_key: "pito.chat.show.needs_ref")
      expect(payload["message_args"]).to eq({})
    end

    it "includes message_args when provided" do
      payload = described_class.call(
        message_key:  "pito.chat.errors.cannot_list",
        message_args: { noun: "videos" }
      )
      expect(payload["message_args"]).to eq({ noun: "videos" })
    end

    it "renders without raising" do
      expect { described_class.call(message_key: "pito.chat.show.needs_ref") }.not_to raise_error
    end
  end
end
