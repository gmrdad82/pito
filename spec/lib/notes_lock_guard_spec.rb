require "rails_helper"

RSpec.describe NotesLockGuard do
  let(:tenant) { create(:tenant) }

  describe ".locked?" do
    it "returns false when no notes_syncing_at is set" do
      tenant.update!(notes_syncing_at: nil)
      expect(described_class.locked?(tenant)).to be false
    end

    it "returns true when notes_syncing_at is fresh (within 5 min)" do
      tenant.update!(notes_syncing_at: 1.minute.ago)
      expect(described_class.locked?(tenant)).to be true
    end

    it "returns false when notes_syncing_at is stale (> 5 min)" do
      tenant.update!(notes_syncing_at: 10.minutes.ago)
      expect(described_class.locked?(tenant)).to be false
    end

    it "returns false for nil tenant" do
      expect(described_class.locked?(nil)).to be false
    end
  end

  describe ".retry_after_seconds" do
    it "returns 30" do
      expect(described_class.retry_after_seconds).to eq(30)
    end
  end
end
