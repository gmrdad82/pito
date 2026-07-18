# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeviceToken, type: :model do
  describe "validations" do
    it "is valid with a token" do
      expect(DeviceToken.new(token: "abc123", last_seen_at: Time.current)).to be_valid
    end

    it "is invalid without a token" do
      expect(DeviceToken.new(token: nil, last_seen_at: Time.current)).not_to be_valid
    end

    it "is invalid with a blank token" do
      expect(DeviceToken.new(token: "", last_seen_at: Time.current)).not_to be_valid
    end

    it "is invalid with a duplicate token" do
      DeviceToken.create!(token: "abc123", last_seen_at: Time.current)
      dup = DeviceToken.new(token: "abc123", last_seen_at: Time.current)
      expect(dup).not_to be_valid
    end

    it "defaults platform to android" do
      expect(DeviceToken.new.platform).to eq("android")
    end
  end
end
