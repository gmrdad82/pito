require "rails_helper"

# Post-Phase-25 rollback. Pending-approval state machine is gone;
# remaining states are `active`, `expired`, `revoked` (enum value
# `1`, formerly `pending_approval`, stays RESERVED).
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
      record, plaintext = Session.create_for!(user: user, ip: "10.0.0.5", user_agent: "ua")
      expect(record).to be_persisted
      expect(plaintext).to be_a(String).and have_attributes(length: a_value > 32)
      expect(record.token_digest).to eq(Pito::TokenDigest.call(plaintext))
    end

    it "stamps last_activity_at on creation" do
      record, _ = Session.create_for!(user: user, ip: nil, user_agent: nil)
      expect(record.last_activity_at).to be_within(2.seconds).of(Time.current)
    end

    # 2026-05-16 (sessions revamp v2). The public signature is fixed
    # at (user:, ip:, user_agent:). The `remember:` kwarg + the
    # `sessions.remember` column it threaded into are gone.
    it "exposes the minimal keyword surface (user / ip / user_agent)" do
      expect(Session.method(:create_for!).parameters.map(&:last)).to match_array(%i[user ip user_agent])
    end

    it "rejects a stray remember: keyword (the column is gone)" do
      expect {
        Session.create_for!(user: user, ip: nil, user_agent: nil, remember: true)
      }.to raise_error(ArgumentError)
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

  describe "enum :state" do
    it "defines the post-rollback enum (active / expired / revoked)" do
      expect(Session.states).to eq("active" => 0, "expired" => 2, "revoked" => 3)
    end

    it "defaults to :active on a fresh row" do
      session = create(:session)
      expect(session.state).to eq("active")
    end

    # Rails 8.1 regression guard. The `enum :state` declaration is
    # paired with `attribute :state, :integer` so the column type is
    # locked ahead of the enum macro. Without that pairing, Rails
    # 8.1's enum type inference can fail under autoload races /
    # bootsnap cache and raise
    # `Undeclared attribute type for enum 'state' in Session`.
    it "pins :state to the :integer attribute type" do
      expect(Session.attribute_types["state"].type).to eq(:integer)
    end

    it "reserves value 1 (the dropped pending_approval state) so it cannot collide with future kinds" do
      expect(Session.states.values).not_to include(1)
    end
  end

  describe "scope :active_sessions" do
    it "returns active, non-revoked rows" do
      active = create(:session)
      expired = create(:session, :expired)
      revoked = create(:session, :revoked_state)
      expect(Session.active_sessions).to include(active)
      expect(Session.active_sessions).not_to include(expired, revoked)
    end
  end

  describe "#revoke! sets enum state too" do
    it "sets state to :revoked alongside revoked_at" do
      session = create(:session)
      session.revoke!
      session.reload
      expect(session.state).to eq("revoked")
      expect(session.revoked_at).to be_present
    end
  end
end
