require "rails_helper"

RSpec.describe BlockedLocation, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:blocked_by_user).class_name("User") }
    it { is_expected.to belong_to(:unblocked_by_user).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:fingerprint_hash) }
    it { is_expected.to validate_length_of(:fingerprint_hash).is_equal_to(64) }
    it { is_expected.to validate_presence_of(:ip_prefix) }

    it "rejects a malformed ip_prefix CIDR" do
      row = build(:blocked_location, ip_prefix: "garbage")
      expect(row).not_to be_valid
      expect(row.errors[:ip_prefix]).to include("is not a valid CIDR")
    end

    it "enforces unique (fingerprint_hash, ip_prefix) at the DB level" do
      first = create(:blocked_location)
      dup = build(
        :blocked_location,
        fingerprint_hash: first.fingerprint_hash,
        ip_prefix: first.ip_prefix
      )
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "stamps blocked_at on create when omitted" do
      row = create(:blocked_location, blocked_at: nil)
      expect(row.blocked_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe ".for_pair?" do
    let(:fp) { Digest::SHA256.hexdigest("pair-1") }
    let(:ip_prefix) { "10.5.5.0/24" }

    it "returns true when an active block exists" do
      create(:blocked_location, fingerprint_hash: fp, ip_prefix: ip_prefix)
      expect(described_class.for_pair?(fp, ip_prefix)).to be true
    end

    it "returns false for an unblocked row" do
      create(:blocked_location, :unblocked, fingerprint_hash: fp, ip_prefix: ip_prefix)
      expect(described_class.for_pair?(fp, ip_prefix)).to be false
    end

    it "returns false when fp or prefix is blank" do
      expect(described_class.for_pair?(nil, ip_prefix)).to be false
      expect(described_class.for_pair?(fp, nil)).to be false
      expect(described_class.for_pair?("", "")).to be false
    end

    it "returns false when no row matches" do
      expect(described_class.for_pair?(fp, ip_prefix)).to be false
    end
  end

  describe "scopes" do
    it "active excludes rows with unblocked_at set" do
      a = create(:blocked_location)
      b = create(:blocked_location, :unblocked)
      expect(described_class.active).to contain_exactly(a)
      expect(described_class.active).not_to include(b)
    end

    it "for_pair filters by fingerprint and ip_prefix tuple" do
      row = create(:blocked_location, fingerprint_hash: "f" * 64, ip_prefix: "10.0.0.0/24")
      create(:blocked_location, fingerprint_hash: "a" * 64, ip_prefix: "10.0.0.0/24")
      expect(described_class.for_pair("f" * 64, "10.0.0.0/24")).to contain_exactly(row)
    end
  end

  describe ".bump_attempt!" do
    let!(:row) { create(:blocked_location, fingerprint_hash: "b" * 64, ip_prefix: "10.10.0.0/24") }

    it "increments attempt_count and stamps last_attempt_at" do
      expect {
        described_class.bump_attempt!("b" * 64, "10.10.0.0/24")
      }.to change { row.reload.attempt_count }.by(1)
      expect(row.last_attempt_at).to be_within(2.seconds).of(Time.current)
    end

    it "is a no-op when no matching row exists" do
      expect {
        described_class.bump_attempt!("c" * 64, "10.10.0.0/24")
      }.not_to change { row.reload.attempt_count }
    end

    it "is a no-op when fp / prefix are blank" do
      expect {
        described_class.bump_attempt!(nil, nil)
      }.not_to change { row.reload.attempt_count }
    end

    it "does not bump unblocked rows" do
      row.update!(unblocked_at: Time.current, unblocked_by_user: create(:user))
      expect {
        described_class.bump_attempt!(row.fingerprint_hash, row.ip_prefix)
      }.not_to change { row.reload.attempt_count }
    end
  end

  describe "#active?" do
    it "is true when unblocked_at is nil" do
      expect(build(:blocked_location).active?).to be true
    end

    it "is false when unblocked_at is set" do
      expect(build(:blocked_location, :unblocked).active?).to be false
    end
  end

  describe "source_surface enum" do
    it "lists the three surfaces in order" do
      expect(described_class.source_surfaces.keys).to eq(%w[web tui mcp])
    end
  end
end
