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
end
