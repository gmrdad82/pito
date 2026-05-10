require "rails_helper"

# Phase 12 — Step A. `SessionThrottle` is the failed-login bucket
# (10 / 5 minutes) read by `SessionsController#create` on every failure
# path and by the rack-attack blocklist via `exhausted?`. Independent
# from the `ApiAuthThrottle` (failed-bearer) bucket — its cache key
# prefix (`pito:login_failed:`) keeps the two from sharing state.
RSpec.describe SessionThrottle do
  before do
    Rack::Attack.cache.store.clear if Rack::Attack.cache.store.respond_to?(:clear)
  end

  describe "constants" do
    it "limits to 10 failures per window" do
      expect(described_class::LIMIT).to eq(10)
    end

    it "uses a 5-minute window" do
      expect(described_class::WINDOW).to eq(5.minutes)
    end
  end

  describe ".bucket_key" do
    it "namespaces under pito:login_failed: with the IP suffix" do
      key = described_class.bucket_key("198.51.100.7")
      expect(key).to start_with("pito:login_failed:")
      expect(key).to end_with(":198.51.100.7")
    end

    it "rotates the window-index segment when WINDOW elapses" do
      base = Time.utc(2026, 5, 10, 12, 0, 0)
      allow(Time).to receive(:now).and_return(base)
      a = described_class.bucket_key("10.0.0.1")

      allow(Time).to receive(:now).and_return(base + described_class::WINDOW + 1.second)
      b = described_class.bucket_key("10.0.0.1")

      expect(a).not_to eq(b)
    end

    it "is stable for two reads inside the same window" do
      a = described_class.bucket_key("10.0.0.1")
      b = described_class.bucket_key("10.0.0.1")
      expect(a).to eq(b)
    end

    it "produces different keys for different IPs" do
      expect(described_class.bucket_key("10.0.0.1"))
        .not_to eq(described_class.bucket_key("10.0.0.2"))
    end
  end

  describe ".record_failure" do
    it "increments the bucket counter for the given IP" do
      ip = "203.0.113.10"
      described_class.record_failure(ip)
      key = described_class.bucket_key(ip)
      expect(Rack::Attack.cache.store.read(key).to_i).to eq(1)
    end

    it "supports multiple increments under the same key" do
      ip = "203.0.113.20"
      3.times { described_class.record_failure(ip) }
      key = described_class.bucket_key(ip)
      expect(Rack::Attack.cache.store.read(key).to_i).to eq(3)
    end

    it "no-ops on a blank ip (empty string)" do
      expect {
        described_class.record_failure("")
      }.not_to raise_error
    end

    it "no-ops on a nil ip" do
      expect {
        described_class.record_failure(nil)
      }.not_to raise_error
    end

    it "swallows underlying cache-store errors" do
      allow(Rack::Attack.cache.store).to receive(:increment).and_raise(StandardError, "boom")
      expect {
        described_class.record_failure("203.0.113.30")
      }.not_to raise_error
    end
  end

  describe ".exhausted?" do
    it "returns false when the bucket is empty" do
      expect(described_class.exhausted?("198.51.100.40")).to be(false)
    end

    it "returns false on a blank ip" do
      expect(described_class.exhausted?("")).to be(false)
      expect(described_class.exhausted?(nil)).to be(false)
    end

    it "returns false below the LIMIT" do
      ip = "198.51.100.41"
      9.times { described_class.record_failure(ip) }
      expect(described_class.exhausted?(ip)).to be(false)
    end

    it "returns true at the LIMIT (boundary)" do
      ip = "198.51.100.42"
      10.times { described_class.record_failure(ip) }
      expect(described_class.exhausted?(ip)).to be(true)
    end

    it "returns true above the LIMIT" do
      ip = "198.51.100.43"
      11.times { described_class.record_failure(ip) }
      expect(described_class.exhausted?(ip)).to be(true)
    end

    it "swallows underlying cache-store errors and returns false" do
      allow(Rack::Attack.cache.store).to receive(:read).and_raise(StandardError, "boom")
      expect(described_class.exhausted?("198.51.100.50")).to be(false)
    end
  end

  describe "flaw — bucket isolation between IPs" do
    it "does not flag IP B because IP A exhausted its bucket" do
      ip_a = "198.51.100.91"
      ip_b = "198.51.100.92"
      10.times { described_class.record_failure(ip_a) }
      expect(described_class.exhausted?(ip_a)).to be(true)
      expect(described_class.exhausted?(ip_b)).to be(false)
    end
  end
end
