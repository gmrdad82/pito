# frozen_string_literal: true

# spec/services/pito/auth/backoff_calculator_spec.rb
#
# Contract: Pito::Auth::BackoffCalculator
#   .record_trip!(key:)        → Integer (backoff seconds); persists trip counter
#   .seconds_remaining(key:)   → Integer (current backoff for the key, 0 if clear)
#   .reset!(key:)              → true; clears the bucket
#
# Growth: 60, 120, 240, 480, 960, 1920, 3600 (capped at MAX_BACKOFF = 3600).
# Fail-open: cache errors return BASE_BACKOFF / 0 / false without raising.
#
# Note: The test environment uses :null_store (nothing persists). We swap
# Rails.cache to an ActiveSupport::Cache::MemoryStore for these examples so
# that the persistence and doubling logic can be exercised.

require "rails_helper"

RSpec.describe Pito::Auth::BackoffCalculator do
  let(:key) { "ip:test_#{SecureRandom.hex(4)}" }  # unique key per example
  let(:mem_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(described_class).to receive(:cache).and_return(mem_cache)
  end

  after do
    mem_cache.clear
  end

  describe ".record_trip!" do
    it "returns BASE_BACKOFF on the first trip" do
      expect(described_class.record_trip!(key: key)).to eq(described_class::BASE_BACKOFF)
    end

    it "doubles the window on the second trip" do
      described_class.record_trip!(key: key)
      expect(described_class.record_trip!(key: key)).to eq(described_class::BASE_BACKOFF * 2)
    end

    it "doubles again on the third trip" do
      2.times { described_class.record_trip!(key: key) }
      expect(described_class.record_trip!(key: key)).to eq(described_class::BASE_BACKOFF * 4)
    end

    it "caps at MAX_BACKOFF after many trips" do
      # Force enough trips to exceed the cap.
      10.times { described_class.record_trip!(key: key) }
      expect(described_class.record_trip!(key: key)).to eq(described_class::MAX_BACKOFF)
    end

    it "returns BASE_BACKOFF for an empty key (guard branch)" do
      expect(described_class.record_trip!(key: "")).to eq(described_class::BASE_BACKOFF)
    end
  end

  describe ".backoff_for_count" do
    {
      1 => 60,
      2 => 120,
      3 => 240,
      4 => 480,
      5 => 960,
      6 => 1920,
      7 => 3600,
      8 => 3600
    }.each do |count, expected|
      it "count=#{count} → #{expected}s" do
        expect(described_class.backoff_for_count(count)).to eq(expected)
      end
    end

    it "count=0 is treated as 1 (minimum)" do
      expect(described_class.backoff_for_count(0)).to eq(described_class::BASE_BACKOFF)
    end

    it "negative count is treated as 1 (minimum)" do
      expect(described_class.backoff_for_count(-5)).to eq(described_class::BASE_BACKOFF)
    end
  end

  describe ".seconds_remaining" do
    it "returns 0 when no trips have been recorded" do
      fresh_key = "ip:fresh_#{SecureRandom.hex(4)}"
      expect(described_class.seconds_remaining(key: fresh_key)).to eq(0)
    end

    it "returns BASE_BACKOFF after one trip" do
      described_class.record_trip!(key: key)
      expect(described_class.seconds_remaining(key: key)).to eq(described_class::BASE_BACKOFF)
    end

    it "returns 0 for an empty key" do
      expect(described_class.seconds_remaining(key: "")).to eq(0)
    end
  end

  describe ".reset!" do
    it "returns true on success" do
      described_class.record_trip!(key: key)
      expect(described_class.reset!(key: key)).to be true
    end

    it "clears the trip count so seconds_remaining returns 0" do
      described_class.record_trip!(key: key)
      described_class.reset!(key: key)
      expect(described_class.seconds_remaining(key: key)).to eq(0)
    end

    it "next trip after reset starts from BASE_BACKOFF again" do
      described_class.record_trip!(key: key)
      described_class.record_trip!(key: key)
      described_class.reset!(key: key)
      expect(described_class.record_trip!(key: key)).to eq(described_class::BASE_BACKOFF)
    end

    it "returns false for an empty key" do
      expect(described_class.reset!(key: "")).to be false
    end
  end
end
