require "rails_helper"

# Phase 25 — 01g. Stale-session sweeper. Revokes active sessions
# idle longer than `STALE_AFTER` (30 days).
RSpec.describe SessionStaleSweeperJob do
  let(:user) { create(:user) }

  describe "#perform" do
    it "revokes sessions whose last_activity_at is older than STALE_AFTER" do
      stale = create(:session, user: user, last_activity_at: 31.days.ago)
      fresh = create(:session, user: user, last_activity_at: 1.hour.ago)

      expect { described_class.new.perform }
        .to change { stale.reload.revoked? }.from(false).to(true)

      expect(fresh.reload.revoked?).to be false
    end

    it "sweeps sessions with nil last_activity_at created beyond STALE_AFTER" do
      stale = create(:session, user: user, last_activity_at: nil,
                     created_at: 45.days.ago)

      expect { described_class.new.perform }
        .to change { stale.reload.revoked? }.from(false).to(true)
    end

    it "leaves already-revoked sessions alone (idempotent)" do
      revoked = create(:session, :revoked_state, user: user,
                       last_activity_at: 60.days.ago)
      original_revoked_at = revoked.revoked_at

      described_class.new.perform

      revoked.reload
      expect(revoked.revoked_at.to_i).to eq(original_revoked_at.to_i)
    end

    it "leaves pending sessions alone (they have their own sweeper)" do
      pending = create(:session, :pending, user: user,
                       last_activity_at: 60.days.ago)

      described_class.new.perform

      pending.reload
      expect(pending.state_pending_approval?).to be true
      expect(pending.revoked?).to be false
    end

    it "returns the count of revoked rows" do
      create_list(:session, 3, user: user, last_activity_at: 40.days.ago)
      create(:session, user: user, last_activity_at: 1.day.ago)

      expect(described_class.new.perform).to eq(3)
    end

    it "returns 0 when nothing is stale" do
      create(:session, user: user, last_activity_at: 1.hour.ago)
      expect(described_class.new.perform).to eq(0)
    end

    it "stamps revoked_at and bumps state to :revoked" do
      stale = create(:session, user: user, last_activity_at: 31.days.ago)

      described_class.new.perform

      stale.reload
      expect(stale.revoked_at).to be_present
      expect(stale.state_revoked?).to be true
    end
  end
end
