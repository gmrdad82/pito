# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::CompactTimeAgo do
  subject(:call) { described_class.call(time) }

  describe "nil input" do
    let(:time) { nil }

    it { is_expected.to eq("never") }
  end

  describe "seconds tier (0..59s)" do
    it "returns ~0s ago for now" do
      expect(described_class.call(Time.current)).to eq("~0s ago")
    end

    it "returns ~0s ago for future-stamped time (negative clamp)" do
      expect(described_class.call(1.minute.from_now)).to eq("~0s ago")
    end

    it "returns ~30s ago for 30 seconds ago" do
      expect(described_class.call(30.seconds.ago)).to eq("~30s ago")
    end

    it "returns ~59s ago for 59 seconds ago" do
      expect(described_class.call(59.seconds.ago)).to eq("~59s ago")
    end
  end

  describe "minutes tier (60s..3599s)" do
    it "returns ~1m ago for exactly 60 seconds ago" do
      expect(described_class.call(60.seconds.ago)).to eq("~1m ago")
    end

    it "returns ~1m ago for 89 seconds ago (floors down)" do
      expect(described_class.call(89.seconds.ago)).to eq("~1m ago")
    end

    it "returns ~45m ago for 45 minutes ago" do
      expect(described_class.call(45.minutes.ago)).to eq("~45m ago")
    end

    it "returns ~59m ago for 3599 seconds ago" do
      expect(described_class.call(3599.seconds.ago)).to eq("~59m ago")
    end
  end

  describe "hours tier (3600s..86399s)" do
    it "returns ~1h ago for exactly 1 hour ago" do
      expect(described_class.call(1.hour.ago)).to eq("~1h ago")
    end

    it "returns ~2h ago for 2 hours ago" do
      expect(described_class.call(2.hours.ago)).to eq("~2h ago")
    end

    it "returns ~23h ago for 23 hours ago" do
      expect(described_class.call(23.hours.ago)).to eq("~23h ago")
    end
  end

  describe "days tier (86400s..2591999s)" do
    it "returns ~1d ago for exactly 1 day ago" do
      expect(described_class.call(1.day.ago)).to eq("~1d ago")
    end

    it "returns ~7d ago for 7 days ago" do
      expect(described_class.call(7.days.ago)).to eq("~7d ago")
    end

    it "returns ~29d ago for 29 days ago" do
      expect(described_class.call(29.days.ago)).to eq("~29d ago")
    end
  end

  describe "months tier (2592000s..31535999s)" do
    it "returns ~1mo ago for exactly 30 days ago" do
      expect(described_class.call(30.days.ago)).to eq("~1mo ago")
    end

    it "returns ~6mo ago for 6 months ago" do
      expect(described_class.call(180.days.ago)).to eq("~6mo ago")
    end

    it "returns ~11mo ago for 335 days ago" do
      expect(described_class.call(335.days.ago)).to eq("~11mo ago")
    end
  end

  describe "years tier (31536000s+)" do
    it "returns ~1yr ago for exactly 365 days ago" do
      expect(described_class.call(365.days.ago)).to eq("~1yr ago")
    end

    it "returns ~2yr ago for 2 years ago" do
      expect(described_class.call(730.days.ago)).to eq("~2yr ago")
    end

    it "returns ~10yr ago for 10 years ago" do
      expect(described_class.call(3650.days.ago)).to eq("~10yr ago")
    end
  end

  describe "format shape" do
    it "always matches ~\\d+(s|m|h|d|mo|yr) ago or 'never'" do
      samples = [
        nil, Time.current, 45.seconds.ago, 5.minutes.ago,
        3.hours.ago, 2.days.ago, 2.months.ago, 2.years.ago
      ]
      samples.each do |t|
        result = described_class.call(t)
        expect(result).to match(/\Anever\z|\A~\d+(s|m|h|d|mo|yr) ago\z/),
          "unexpected format for #{t.inspect}: #{result.inspect}"
      end
    end
  end
end
