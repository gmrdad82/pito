# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ExternalApiTracker::Igdb do
  describe "constants" do
    it "defines ROLLING_WINDOW as 60 seconds" do
      expect(described_class::ROLLING_WINDOW).to eq(60)
    end

    it "defines RATE_LIMIT_PER_SECOND as 4" do
      expect(described_class::RATE_LIMIT_PER_SECOND).to eq(4)
    end
  end

  describe ".usage" do
    it "returns an integer (skeleton returns 0)" do
      expect(described_class.usage).to be_a(Integer)
    end
  end

  describe ".quota" do
    it "returns RATE_LIMIT_PER_SECOND * ROLLING_WINDOW" do
      expect(described_class.quota).to eq(4 * 60)
    end
  end

  describe ".window" do
    it "returns :rolling_60s" do
      expect(described_class.window).to eq(:rolling_60s)
    end
  end

  describe ".percent" do
    it "returns a Float in 0.0..1.0" do
      p = described_class.percent
      expect(p).to be_a(Float)
      expect(p).to be_between(0.0, 1.0).inclusive
    end

    it "returns 0.0 when usage is 0" do
      allow(described_class).to receive(:usage).and_return(0)
      expect(described_class.percent).to eq(0.0)
    end

    it "clamps above 1.0 (usage > quota)" do
      allow(described_class).to receive(:usage).and_return(9999)
      expect(described_class.percent).to eq(1.0)
    end
  end

  describe ".status" do
    it "returns :ok when percent is low" do
      allow(described_class).to receive(:percent).and_return(0.5)
      expect(described_class.status).to eq(:ok)
    end

    it "returns :warn at 0.7" do
      allow(described_class).to receive(:percent).and_return(0.7)
      expect(described_class.status).to eq(:warn)
    end

    it "returns :critical at 0.9" do
      allow(described_class).to receive(:percent).and_return(0.9)
      expect(described_class.status).to eq(:critical)
    end

    it "returns :critical above 0.9" do
      allow(described_class).to receive(:percent).and_return(1.0)
      expect(described_class.status).to eq(:critical)
    end

    it "returns a symbol from the known set" do
      expect(%i[ok warn critical]).to include(described_class.status)
    end
  end
end
