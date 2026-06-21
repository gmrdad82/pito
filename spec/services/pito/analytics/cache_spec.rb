# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Cache, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:sig)     { "test:analytics:#{SecureRandom.hex(4)}" }
  let(:payload) { { "views" => 1_234, "subs" => 567 } }

  # ── read ──────────────────────────────────────────────────────────────────

  describe ".read" do
    it "returns nil when no row exists" do
      expect(described_class.read(sig)).to be_nil
    end

    it "returns nil for a pending row" do
      create(:analytics_cache, signature: sig, status: "pending")
      expect(described_class.read(sig)).to be_nil
    end

    it "returns nil for a failed row" do
      create(:analytics_cache, :failed, signature: sig)
      expect(described_class.read(sig)).to be_nil
    end

    it "returns nil for a ready but expired row" do
      create(:analytics_cache, :expired, signature: sig)
      expect(described_class.read(sig)).to be_nil
    end

    it "returns the payload for a ready, unexpired row" do
      create(:analytics_cache, :ready, signature: sig, payload: payload)
      expect(described_class.read(sig)).to eq(payload)
    end

    it "returns the payload when expires_at is nil (permanent row)" do
      create(:analytics_cache, :ready, signature: sig, payload: payload, expires_at: nil)
      expect(described_class.read(sig)).to eq(payload)
    end
  end

  # ── status ────────────────────────────────────────────────────────────────

  describe ".status" do
    it "returns :missing when no row exists" do
      expect(described_class.status(sig)).to eq(:missing)
    end

    it "returns :pending for a pending row" do
      create(:analytics_cache, signature: sig, status: "pending")
      expect(described_class.status(sig)).to eq(:pending)
    end

    it "returns :failed for a failed row" do
      create(:analytics_cache, :failed, signature: sig)
      expect(described_class.status(sig)).to eq(:failed)
    end

    it "returns :ready for a ready, unexpired row" do
      create(:analytics_cache, :ready, signature: sig)
      expect(described_class.status(sig)).to eq(:ready)
    end

    it "returns :missing for a ready but expired row" do
      create(:analytics_cache, :expired, signature: sig)
      expect(described_class.status(sig)).to eq(:missing)
    end
  end

  # ── store ─────────────────────────────────────────────────────────────────

  describe ".store" do
    it "creates a ready row with payload and expires_at when none exists" do
      described_class.store(sig, payload, ttl: 1.hour)

      row = AnalyticsCache.find_by!(signature: sig)
      expect(row.status).to eq("ready")
      expect(row.payload).to eq(payload)
      expect(row.expires_at).to be_within(5.seconds).of(1.hour.from_now)
    end

    it "clears the error field when storing" do
      create(:analytics_cache, :failed, signature: sig)
      described_class.store(sig, payload, ttl: 1.hour)

      expect(AnalyticsCache.find_by!(signature: sig).error).to be_nil
    end

    it "overwrites an existing ready row" do
      create(:analytics_cache, :ready, signature: sig, payload: { "old" => 1 })
      described_class.store(sig, payload, ttl: 2.hours)

      row = AnalyticsCache.find_by!(signature: sig)
      expect(row.payload).to eq(payload)
      expect(row.expires_at).to be_within(5.seconds).of(2.hours.from_now)
    end
  end

  # ── fail ──────────────────────────────────────────────────────────────────

  describe ".fail" do
    it "creates a failed row when none exists" do
      described_class.fail(sig, error: "boom")
      row = AnalyticsCache.find_by!(signature: sig)
      expect(row.status).to eq("failed")
      expect(row.error).to eq("boom")
    end

    it "updates an existing pending row to failed" do
      create(:analytics_cache, signature: sig, status: "pending")
      described_class.fail(sig, error: "timeout")
      expect(AnalyticsCache.find_by!(signature: sig).status).to eq("failed")
    end

    it "truncates error messages longer than ERROR_MAX characters" do
      long_error = "x" * (Pito::Analytics::Cache::ERROR_MAX + 500)
      described_class.fail(sig, error: long_error)
      stored = AnalyticsCache.find_by!(signature: sig).error
      expect(stored.length).to be <= Pito::Analytics::Cache::ERROR_MAX
    end
  end

  # ── claim ─────────────────────────────────────────────────────────────────

  describe ".claim" do
    context "when no row exists" do
      it "returns :claimed and creates a pending row" do
        result = described_class.claim(sig)
        expect(result).to eq(:claimed)
        expect(AnalyticsCache.find_by!(signature: sig).status).to eq("pending")
      end
    end

    context "when a pending row already exists" do
      before { create(:analytics_cache, signature: sig, status: "pending") }

      it "returns :pending without creating a duplicate" do
        expect(described_class.claim(sig)).to eq(:pending)
        expect(AnalyticsCache.where(signature: sig).count).to eq(1)
      end
    end

    context "when a ready, unexpired row exists" do
      before { create(:analytics_cache, :ready, signature: sig) }

      it "returns :ready" do
        expect(described_class.claim(sig)).to eq(:ready)
      end
    end

    context "when a ready but expired row exists" do
      before { create(:analytics_cache, :expired, signature: sig) }

      it "returns :claimed and resets the row to pending" do
        result = described_class.claim(sig)
        expect(result).to eq(:claimed)
        row = AnalyticsCache.find_by!(signature: sig)
        expect(row.status).to eq("pending")
        expect(row.payload).to be_nil
        expect(row.expires_at).to be_nil
      end
    end

    context "when a failed row exists" do
      before { create(:analytics_cache, :failed, signature: sig) }

      it "returns :claimed and resets the row to pending" do
        result = described_class.claim(sig)
        expect(result).to eq(:claimed)
        row = AnalyticsCache.find_by!(signature: sig)
        expect(row.status).to eq("pending")
        expect(row.error).to be_nil
      end
    end

    context "full lifecycle: claim → store → re-claim after expiry" do
      it "moves through :claimed → :ready → :claimed after TTL" do
        # First claim — no row
        expect(described_class.claim(sig)).to eq(:claimed)

        # Store result
        described_class.store(sig, payload, ttl: 1.second)
        expect(described_class.claim(sig)).to eq(:ready)

        # Travel past the TTL
        travel_to 2.seconds.from_now do
          expect(described_class.claim(sig)).to eq(:claimed)
        end
      end
    end

    context "race-condition simulation" do
      it "returns :pending when another worker has just inserted a pending row (RecordNotUnique rescued)" do
        # Simulate the race: row does not exist when we enter claim, but
        # another thread inserts before our INSERT fires.
        allow(AnalyticsCache).to receive(:find_by).and_return(nil)
        allow(AnalyticsCache).to receive(:create!)
          .and_raise(ActiveRecord::RecordNotUnique)

        pending_row = build_stubbed(:analytics_cache, signature: sig, status: "pending")
        allow(AnalyticsCache).to receive(:find_by!).and_return(pending_row)

        expect(described_class.claim(sig)).to eq(:pending)
      end
    end
  end

  # ── fetch ─────────────────────────────────────────────────────────────────

  describe ".fetch" do
    it "calls the block on a cache miss and returns the result" do
      calls = 0
      result = described_class.fetch(sig, ttl: 1.hour) do
        calls += 1
        payload
      end
      expect(calls).to eq(1)
      expect(result).to eq(payload)
    end

    it "stores the result so a second call hits the cache (block runs once)" do
      calls = 0
      block = -> { calls += 1; payload }

      described_class.fetch(sig, ttl: 1.hour, &block)
      second_result = described_class.fetch(sig, ttl: 1.hour, &block)

      expect(calls).to eq(1)
      expect(second_result).to eq(payload)
    end

    it "returns the cached value without calling the block on a hit" do
      create(:analytics_cache, :ready, signature: sig, payload: payload)
      calls = 0
      result = described_class.fetch(sig, ttl: 1.hour) { calls += 1; {} }
      expect(calls).to eq(0)
      expect(result).to eq(payload)
    end

    it "marks the entry as failed and re-raises when the block raises" do
      expect {
        described_class.fetch(sig, ttl: 1.hour) { raise "compute error" }
      }.to raise_error(RuntimeError, "compute error")

      expect(described_class.status(sig)).to eq(:failed)
    end

    it "re-computes after TTL expiry (block called again)" do
      calls = 0
      described_class.fetch(sig, ttl: 1.second) { calls += 1; payload }

      travel_to 2.seconds.from_now do
        described_class.fetch(sig, ttl: 1.second) { calls += 1; payload }
      end

      expect(calls).to eq(2)
    end
  end

  # ── sweep ─────────────────────────────────────────────────────────────────

  describe ".sweep" do
    it "returns 0 when there is nothing to delete" do
      expect(described_class.sweep).to eq(0)
    end

    it "deletes expired rows and returns the count" do
      create(:analytics_cache, :expired, signature: "#{sig}:a")
      create(:analytics_cache, :expired, signature: "#{sig}:b")
      create(:analytics_cache, :ready,   signature: "#{sig}:c") # unexpired

      expect(described_class.sweep).to eq(2)
      expect(AnalyticsCache.find_by(signature: "#{sig}:c")).to be_present
    end

    it "does not delete rows with nil expires_at (permanent)" do
      create(:analytics_cache, :ready, signature: sig, expires_at: nil)
      expect(described_class.sweep).to eq(0)
    end

    it "does not delete pending rows (which have no expires_at)" do
      create(:analytics_cache, signature: sig, status: "pending", expires_at: nil)
      expect(described_class.sweep).to eq(0)
    end
  end
end
