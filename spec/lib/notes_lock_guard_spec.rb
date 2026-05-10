require "rails_helper"

# Phase 8 — tenant drop. The lock is install-wide (an AppSetting key).
RSpec.describe NotesLockGuard do
  before { described_class.release! }
  after  { described_class.release! }

  describe ".locked?" do
    it "returns false when no lock has been acquired" do
      expect(described_class.locked?).to be false
    end

    it "returns true when the lock is fresh (within 5 min)" do
      described_class.acquire!
      expect(described_class.locked?).to be true
    end

    it "returns false when the lock is stale (> 5 min)" do
      AppSetting.set(NotesLockGuard::KEY, 10.minutes.ago.iso8601(6))
      expect(described_class.locked?).to be false
    end

    it "ignores any positional argument (legacy callers passed a tenant)" do
      described_class.acquire!
      expect(described_class.locked?(nil)).to be true
      expect(described_class.locked?("anything")).to be true
    end
  end

  describe ".acquire! / .release!" do
    it "round-trips" do
      described_class.acquire!
      expect(described_class.locked?).to be true
      described_class.release!
      expect(described_class.locked?).to be false
    end

    it "release! is a no-op when no lock is held" do
      expect { described_class.release! }.not_to raise_error
    end
  end

  describe ".retry_after_seconds" do
    it "returns 30" do
      expect(described_class.retry_after_seconds).to eq(30)
    end
  end
end
