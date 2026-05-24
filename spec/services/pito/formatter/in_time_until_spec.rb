require "rails_helper"

RSpec.describe Pito::Formatter::InTimeUntil do
  include ActiveSupport::Testing::TimeHelpers

  describe ".call" do
    # Freeze "today" so date arithmetic in this spec is deterministic
    # regardless of when the suite runs. `travel_to` is the canonical
    # Rails helper (no external dep).
    around do |ex|
      travel_to(Date.new(2026, 5, 25)) { ex.run }
    end

    it "returns 'unknown' for nil" do
      expect(described_class.call(nil)).to eq("unknown")
    end

    it "returns 'today' for today's date" do
      expect(described_class.call(Date.new(2026, 5, 25))).to eq("today")
    end

    it "returns 'today' for past dates (clamps; sibling of the past-tense formatter)" do
      expect(described_class.call(Date.new(2026, 5, 20))).to eq("today")
    end

    it "returns 'in Nd' for 1..6 days out" do
      expect(described_class.call(Date.new(2026, 5, 26))).to eq("in 1d")
      expect(described_class.call(Date.new(2026, 5, 31))).to eq("in 6d")
    end

    it "returns 'in Nw' for 7..29 days out" do
      expect(described_class.call(Date.new(2026, 6, 1))).to eq("in 1w")
      expect(described_class.call(Date.new(2026, 6, 15))).to eq("in 3w")
    end

    it "returns 'in Nmo' for 30..364 days out" do
      expect(described_class.call(Date.new(2026, 7, 25))).to eq("in 2mo")
    end

    it "returns 'in Nyr' for 365+ days out" do
      expect(described_class.call(Date.new(2027, 5, 25))).to eq("in 1yr")
    end

    it "accepts a Time / DateTime value (converts via to_date)" do
      expect(described_class.call(Time.zone.local(2026, 5, 30))).to eq("in 5d")
    end
  end
end
