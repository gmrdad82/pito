# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stats::Metrics do
  describe ".abbr" do
    it "maps the canonical glyphs (S subs · D vids · V views · L likes · C comms)" do
      expect(described_class.abbr(:subs)).to eq("S")
      expect(described_class.abbr(:vids)).to eq("D")
      expect(described_class.abbr(:views)).to eq("V")
      expect(described_class.abbr(:likes)).to eq("L")
      expect(described_class.abbr(:comms)).to eq("C")
    end

    it "accepts string keys" do
      expect(described_class.abbr("subs")).to eq("S")
    end
  end

  describe ".label" do
    it "resolves the legend word via Pito::Copy" do
      expect(described_class.label(:subs)).to eq("subs")
      expect(described_class.label(:vids)).to eq("vids")
      expect(described_class.label(:comms)).to eq("comms")
    end
  end
end
