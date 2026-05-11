require "rails_helper"

# Phase 12 — Step A. Phase 8 — tenant drop. Sessions are user-scoped
# only; no `tenant_id` and no `unscoped` workaround in `create_for!`.
RSpec.describe Session, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:token_digest) }

    it "rejects two rows with the same token_digest" do
      original = create(:session)
      duplicate = build(:session, token_digest: original.token_digest)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token_digest]).to be_present
    end
  end

  describe ".create_for!" do
    let(:user) { create(:user) }

    it "returns the record and the plaintext exactly once" do
      record, plaintext = Session.create_for!(user: user, ip: "10.0.0.5", user_agent: "ua", remember: false)
      expect(record).to be_persisted
      expect(plaintext).to be_a(String).and have_attributes(length: a_value > 32)
      expect(record.token_digest).to eq(Pito::TokenDigest.call(plaintext))
    end

    it "stamps last_activity_at on creation" do
      record, _ = Session.create_for!(user: user, ip: nil, user_agent: nil, remember: false)
      expect(record.last_activity_at).to be_within(2.seconds).of(Time.current)
    end

    it "respects remember=true" do
      record, _ = Session.create_for!(user: user, ip: nil, user_agent: nil, remember: true)
      expect(record.remember?).to be true
    end

    it "does not pass a tenant: keyword" do
      # Defense-in-depth: the public signature is fixed at
      # (user:, ip:, user_agent:, remember:). Adding tenant: would
      # surface an ArgumentError; the test asserts via `parameters`.
      expect(Session.method(:create_for!).parameters.map(&:last)).to match_array(%i[user ip user_agent remember])
    end
  end

  describe "#touch_activity!" do
    it "updates last_activity_at when stale (>= 5 minutes old)" do
      session = create(:session, last_activity_at: 6.minutes.ago)
      expect { session.touch_activity! }.to change { session.reload.last_activity_at }
    end

    it "no-ops when last_activity_at is fresh (< 5 minutes old)" do
      fresh = 1.minute.ago
      session = create(:session, last_activity_at: fresh)
      expect { session.touch_activity! }.not_to change { session.reload.last_activity_at.to_i }
    end

    it "updates when last_activity_at is nil" do
      session = create(:session, last_activity_at: nil)
      session.touch_activity!
      expect(session.reload.last_activity_at).to be_present
    end
  end

  describe "#revoked? / #revoke!" do
    it "is not revoked by default" do
      session = create(:session)
      expect(session.revoked?).to be false
    end

    it "flips revoked_at and reports revoked? true" do
      session = create(:session)
      session.revoke!
      expect(session.reload.revoked?).to be true
      expect(session.revoked_at).to be_within(2.seconds).of(Time.current)
    end

    it "is idempotent — revoking twice does not change revoked_at" do
      session = create(:session)
      session.revoke!
      first = session.reload.revoked_at
      session.revoke!
      expect(session.reload.revoked_at).to eq(first)
    end
  end

  describe "#current?" do
    it "returns true when Current.session is the same row" do
      session = create(:session)
      Current.session = session
      expect(session.current?).to be true
    end

    it "returns false otherwise" do
      session = create(:session)
      Current.session = nil
      expect(session.current?).to be false
    end
  end

  # Phase 25 — 01b (LD-6). Pending-approval state machine specs.
  describe "Phase 25 — 01b state machine" do
    describe "enum :state" do
      it do
        is_expected.to define_enum_for(:state).with_values(
          active: 0,
          pending_approval: 1,
          expired: 2,
          revoked: 3
        ).with_prefix(:state)
      end

      it "defaults to :active on a fresh row" do
        session = create(:session)
        expect(session.state).to eq("active")
      end
    end

    describe "scope :pending" do
      it "returns pending_approval rows regardless of expiry window" do
        active = create(:session)
        pending = create(:session, :pending)
        expired_pending = create(:session, :expired_pending)
        expect(Session.pending).to include(pending, expired_pending)
        expect(Session.pending).not_to include(active)
      end
    end

    describe "scope :expired_pending" do
      it "returns only pending rows whose approval_required_until is in the past" do
        pending = create(:session, :pending)
        expired_pending = create(:session, :expired_pending)
        expect(Session.expired_pending).to include(expired_pending)
        expect(Session.expired_pending).not_to include(pending)
      end
    end

    describe "scope :pending_within_window" do
      it "returns only pending rows whose window is still in the future" do
        pending = create(:session, :pending)
        expired_pending = create(:session, :expired_pending)
        expect(Session.pending_within_window).to include(pending)
        expect(Session.pending_within_window).not_to include(expired_pending)
      end
    end

    describe ".create_pending!" do
      let(:user) { create(:user) }

      it "creates a row in :pending_approval with the 10-minute window" do
        record, plaintext = Session.create_pending!(user: user, ip: "1.2.3.4", user_agent: "ua")
        expect(record).to be_persisted
        expect(plaintext).to be_a(String)
        expect(record.state_pending_approval?).to be true
        expect(record.approval_required_until).to be_within(2.seconds).of(Session::PENDING_APPROVAL_TTL.from_now)
      end
    end

    describe "#pending_within_window?" do
      it "is true for a fresh pending row" do
        expect(create(:session, :pending).pending_within_window?).to be true
      end

      it "is false for an expired-pending row" do
        expect(create(:session, :expired_pending).pending_within_window?).to be false
      end

      it "is false for an :active row" do
        expect(create(:session).pending_within_window?).to be false
      end
    end

    describe "#expired_pending?" do
      it "is true for a pending row past its window" do
        expect(create(:session, :expired_pending).expired_pending?).to be true
      end

      it "is false for an in-window pending row" do
        expect(create(:session, :pending).expired_pending?).to be false
      end
    end

    describe "#expire_if_overdue!" do
      it "flips pending → expired iff past approval_required_until" do
        session = create(:session, :expired_pending)
        expect { session.expire_if_overdue! }.to change { session.reload.state }.from("pending_approval").to("expired")
      end

      it "is a no-op for an in-window pending row" do
        session = create(:session, :pending)
        expect { session.expire_if_overdue! }.not_to change { session.reload.state }
      end

      it "is idempotent on an already-expired row" do
        session = create(:session, :expired)
        expect { session.expire_if_overdue! }.not_to change { session.reload.state }
      end
    end

    describe "#transition_to_active!" do
      it "promotes a pending_approval row to :active and clears the window" do
        session = create(:session, :pending)
        session.transition_to_active!
        session.reload
        expect(session.state).to eq("active")
        expect(session.approval_required_until).to be_nil
      end

      it "raises on an expired row" do
        session = create(:session, :expired)
        expect { session.transition_to_active! }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "raises on a revoked row" do
        session = create(:session, :revoked_state)
        expect { session.transition_to_active! }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe "#revoke!" do
      it "sets state to :revoked alongside revoked_at" do
        session = create(:session)
        session.revoke!
        session.reload
        expect(session.state).to eq("revoked")
        expect(session.revoked_at).to be_present
      end
    end
  end
end
