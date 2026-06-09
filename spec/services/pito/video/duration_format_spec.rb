# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Video::DurationFormat, type: :service do
  describe ".call" do
    it "formats sub-hour durations as M:SS (no leading-zero minute)" do
      expect(described_class.call(574)).to eq("9:34")
      expect(described_class.call(2603)).to eq("43:23")
    end

    it "formats hour-plus durations as H:MM:SS (padded minutes + seconds)" do
      expect(described_class.call(3742)).to eq("1:02:22")
      expect(described_class.call(3632)).to eq("1:00:32")
    end

    it "pads seconds under ten" do
      expect(described_class.call(5)).to eq("0:05")
      expect(described_class.call(65)).to eq("1:05")
    end

    it "handles exactly zero" do
      expect(described_class.call(0)).to eq("0:00")
    end

    it "returns nil for blank or negative input" do
      expect(described_class.call(nil)).to be_nil
      expect(described_class.call(-1)).to be_nil
    end
  end
end
