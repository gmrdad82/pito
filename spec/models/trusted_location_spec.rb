require "rails_helper"

RSpec.describe TrustedLocation, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:fingerprint_hash) }
    it { is_expected.to validate_length_of(:fingerprint_hash).is_equal_to(64) }
    it { is_expected.to validate_presence_of(:ip_prefix) }
    it { is_expected.to validate_presence_of(:first_seen_at) }
    it { is_expected.to validate_presence_of(:last_seen_at) }

    it "rejects an invalid ip_prefix CIDR" do
      row = build(:trusted_location, ip_prefix: "garbage")
      expect(row).not_to be_valid
      expect(row.errors[:ip_prefix]).to include("is not a valid CIDR")
    end

    it "rejects a duplicate (user_id, fingerprint, ip_prefix) triple" do
      first = create(:trusted_location)
      dup = build(
        :trusted_location,
        user: first.user,
        fingerprint_hash: first.fingerprint_hash,
        ip_prefix: first.ip_prefix
      )
      expect(dup).not_to be_valid
      expect(dup.errors[:fingerprint_hash]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let(:user_a) { create(:user) }
    let(:user_b) { create(:user) }
    let!(:row_a) { create(:trusted_location, user: user_a, fingerprint_hash: "a" * 64, ip_prefix: "10.0.0.0/24") }
    let!(:row_b) { create(:trusted_location, user: user_b, fingerprint_hash: "b" * 64, ip_prefix: "10.0.1.0/24") }

    it "for_user scopes by user" do
      expect(described_class.for_user(user_a)).to contain_exactly(row_a)
    end

    it "for_user with nil returns no rows" do
      expect(described_class.for_user(nil)).to be_empty
    end

    it "for_pair scopes by fingerprint + prefix" do
      expect(described_class.for_pair("a" * 64, "10.0.0.0/24")).to contain_exactly(row_a)
    end
  end

  describe ".trusted?" do
    let(:user) { create(:user) }
    let(:fp) { Digest::SHA256.hexdigest("trusted-1") }
    let(:ip_prefix) { "10.20.0.0/24" }

    it "is true when the user/fingerprint/prefix triple has a row" do
      create(:trusted_location, user: user, fingerprint_hash: fp, ip_prefix: ip_prefix)
      expect(described_class.trusted?(user, fp, ip_prefix)).to be true
    end

    it "is false when the triple does not exist" do
      expect(described_class.trusted?(user, fp, ip_prefix)).to be false
    end

    it "is false for blank inputs" do
      expect(described_class.trusted?(nil, fp, ip_prefix)).to be false
      expect(described_class.trusted?(user, nil, ip_prefix)).to be false
      expect(described_class.trusted?(user, fp, nil)).to be false
    end
  end

  # Phase 25 — 01b. Upsert helper used by `Auth::SessionActivator`.
  describe ".touch_for" do
    let(:user) { create(:user) }
    let(:fp) { Digest::SHA256.hexdigest("touch-1") }
    let(:ip_prefix) { "10.30.0.0/24" }

    it "creates the row on first call" do
      expect {
        described_class.touch_for(user: user, fingerprint_hash: fp, ip_prefix: ip_prefix)
      }.to change(described_class, :count).by(1)
      row = described_class.last
      expect(row.user_id).to eq(user.id)
      expect(row.fingerprint_hash).to eq(fp)
      expect(row.ip_prefix).to eq(ip_prefix)
      expect(row.first_seen_at).to be_within(2.seconds).of(Time.current)
      expect(row.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "updates last_seen_at on a repeat call without creating a new row" do
      row = described_class.touch_for(user: user, fingerprint_hash: fp, ip_prefix: ip_prefix)
      row.update_columns(last_seen_at: 1.day.ago)
      expect {
        described_class.touch_for(user: user, fingerprint_hash: fp, ip_prefix: ip_prefix)
      }.not_to change(described_class, :count)
      expect(row.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "raises ArgumentError for missing user" do
      expect {
        described_class.touch_for(user: nil, fingerprint_hash: fp, ip_prefix: ip_prefix)
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for blank fingerprint" do
      expect {
        described_class.touch_for(user: user, fingerprint_hash: "", ip_prefix: ip_prefix)
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for blank ip_prefix" do
      expect {
        described_class.touch_for(user: user, fingerprint_hash: fp, ip_prefix: "")
      }.to raise_error(ArgumentError)
    end
  end
end
