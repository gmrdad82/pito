require "rails_helper"

# Phase 25 — 01g (LD-11). Exponential backoff calculator.
RSpec.describe Auth::BackoffCalculator do
  let(:key) { "ip:1.2.3.4" }

  before { Rack::Attack.cache.store.clear if defined?(Rack::Attack) }

  describe ".record_trip!" do
    it "returns BASE_BACKOFF (60s) on the first trip" do
      expect(described_class.record_trip!(key: key)).to eq(60)
    end

    it "doubles on each consecutive trip" do
      expect(described_class.record_trip!(key: key)).to eq(60)
      expect(described_class.record_trip!(key: key)).to eq(120)
      expect(described_class.record_trip!(key: key)).to eq(240)
      expect(described_class.record_trip!(key: key)).to eq(480)
    end

    it "caps at MAX_BACKOFF (3600s / 1 hour)" do
      # 60 * 2^6 = 3840, so the 7th trip is the first capped.
      results = 8.times.map { described_class.record_trip!(key: key) }
      expect(results).to eq([ 60, 120, 240, 480, 960, 1920, 3600, 3600 ])
    end

    it "tracks each key independently" do
      described_class.record_trip!(key: "ip:1.1.1.1")
      described_class.record_trip!(key: "ip:1.1.1.1")
      expect(described_class.record_trip!(key: "ip:2.2.2.2")).to eq(60)
    end

    it "returns BASE_BACKOFF on an empty key (defensive)" do
      expect(described_class.record_trip!(key: "")).to eq(60)
      expect(described_class.record_trip!(key: nil)).to eq(60)
    end

    it "fails open with BASE_BACKOFF when the cache raises" do
      allow(Rack::Attack.cache.store).to receive(:increment).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:warn).with(/BackoffCalculator/)

      expect(described_class.record_trip!(key: key)).to eq(60)
    end
  end

  describe ".seconds_remaining" do
    it "returns 0 for a key that has never tripped" do
      expect(described_class.seconds_remaining(key: key)).to eq(0)
    end

    it "returns the current backoff window" do
      described_class.record_trip!(key: key)
      expect(described_class.seconds_remaining(key: key)).to eq(60)

      described_class.record_trip!(key: key)
      expect(described_class.seconds_remaining(key: key)).to eq(120)
    end

    it "returns 0 on an empty key" do
      expect(described_class.seconds_remaining(key: "")).to eq(0)
    end

    it "returns 0 when the cache raises" do
      allow(Rack::Attack.cache.store).to receive(:read).and_raise(StandardError)
      expect(described_class.seconds_remaining(key: key)).to eq(0)
    end
  end

  describe ".reset!" do
    it "zeroes the bucket" do
      described_class.record_trip!(key: key)
      described_class.record_trip!(key: key)
      expect(described_class.seconds_remaining(key: key)).to eq(120)

      expect(described_class.reset!(key: key)).to be true
      expect(described_class.seconds_remaining(key: key)).to eq(0)
    end

    it "returns false on an empty key" do
      expect(described_class.reset!(key: "")).to be false
    end

    it "returns false when the cache raises" do
      allow(Rack::Attack.cache.store).to receive(:delete).and_raise(StandardError)
      expect(described_class.reset!(key: key)).to be false
    end
  end

  describe ".backoff_for_count" do
    it "doubles and caps" do
      expect(described_class.backoff_for_count(1)).to eq(60)
      expect(described_class.backoff_for_count(2)).to eq(120)
      expect(described_class.backoff_for_count(7)).to eq(3600)
      expect(described_class.backoff_for_count(99)).to eq(3600)
    end

    it "treats <1 as 1 (defensive)" do
      expect(described_class.backoff_for_count(0)).to eq(60)
      expect(described_class.backoff_for_count(-3)).to eq(60)
    end
  end
end
