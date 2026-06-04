# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel, type: :model do
  describe "#at_handle" do
    it "returns the handle unchanged when it already has a leading @" do
      channel = build(:channel, handle: "@foo")
      expect(channel.at_handle).to eq("@foo")
    end

    it "adds a leading @ when the handle is stored without one" do
      channel = build(:channel, handle: "bar")
      expect(channel.at_handle).to eq("@bar")
    end

    it "never double-prefixes a handle stored as @@something" do
      channel = build(:channel, handle: "@@oops")
      expect(channel.at_handle).to eq("@oops")
    end

    it "handles nil handle gracefully" do
      channel = build(:channel, handle: nil)
      expect(channel.at_handle).to eq("@")
    end
  end
end
