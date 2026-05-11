require "rails_helper"

# Phase 25 — 01e. Auth::BackupCodeConsumer specs.
RSpec.describe Auth::BackupCodeConsumer do
  let(:user) { create(:user) }
  let(:plaintext) { "ABCD2345" }
  let!(:row) do
    user.totp_backup_codes.create!(code_digest: BCrypt::Password.create(plaintext))
  end

  describe ".call (happy path)" do
    it "returns :ok for an unused matching code" do
      expect(described_class.call(user: user, code: plaintext)).to eq(:ok)
    end

    it "stamps used_at on the row" do
      described_class.call(user: user, code: plaintext)
      expect(row.reload.used_at).to be_present
    end

    it "strips whitespace before compare" do
      expect(described_class.call(user: user, code: "  #{plaintext}  ")).to eq(:ok)
    end
  end

  describe ".call (sad path)" do
    it "returns :already_used when the row was already consumed" do
      row.update!(used_at: 1.minute.ago)
      expect(described_class.call(user: user, code: plaintext)).to eq(:already_used)
    end

    it "returns :invalid for a code that does not match any row" do
      expect(described_class.call(user: user, code: "ZZZZ9999")).to eq(:invalid)
    end

    it "returns :invalid on blank input" do
      expect(described_class.call(user: user, code: "")).to eq(:invalid)
      expect(described_class.call(user: user, code: nil)).to eq(:invalid)
    end

    it "raises on a nil user" do
      expect { described_class.call(user: nil, code: plaintext) }.to raise_error(ArgumentError)
    end
  end

  describe ".call (edge: reuse rejection)" do
    it "consume + consume returns :ok then :already_used" do
      expect(described_class.call(user: user, code: plaintext)).to eq(:ok)
      expect(described_class.call(user: user, code: plaintext)).to eq(:already_used)
    end
  end
end
