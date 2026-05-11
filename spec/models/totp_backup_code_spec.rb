require "rails_helper"

# Phase 25 — 01e. TotpBackupCode unit specs.
RSpec.describe TotpBackupCode, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "requires a code_digest" do
      row = described_class.new(user: user)
      expect(row).not_to be_valid
      expect(row.errors[:code_digest]).to be_present
    end

    it "requires a user" do
      row = described_class.new(code_digest: BCrypt::Password.create("ABCD"))
      expect(row).not_to be_valid
      expect(row.errors[:user]).to be_present
    end
  end

  describe "#matches?" do
    let(:plaintext) { "ABCD2345" }
    let(:row) do
      described_class.create!(user: user, code_digest: BCrypt::Password.create(plaintext))
    end

    it "returns true for the matching plaintext" do
      expect(row.matches?(plaintext)).to be true
    end

    it "returns false for a different plaintext" do
      expect(row.matches?("ZZZZ9999")).to be false
    end

    it "returns false on a blank input" do
      expect(row.matches?("")).to be false
      expect(row.matches?(nil)).to be false
    end

    it "returns false (no raise) when the digest column is malformed" do
      row.update_columns(code_digest: "not-a-bcrypt-hash")
      expect(row.matches?(plaintext)).to be false
    end
  end

  describe "scopes" do
    let!(:unused_row) { described_class.create!(user: user, code_digest: BCrypt::Password.create("AAAA1111")) }
    let!(:used_row) do
      described_class.create!(user: user, code_digest: BCrypt::Password.create("BBBB2222"), used_at: Time.current)
    end

    it ".unused excludes rows with used_at stamped" do
      expect(described_class.unused).to contain_exactly(unused_row)
    end

    it ".used returns only used rows" do
      expect(described_class.used).to contain_exactly(used_row)
    end
  end

  describe "#used?" do
    it "is false when used_at is nil" do
      row = described_class.new(used_at: nil)
      expect(row.used?).to be false
    end

    it "is true when used_at is stamped" do
      row = described_class.new(used_at: Time.current)
      expect(row.used?).to be true
    end
  end
end
