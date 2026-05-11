require "rails_helper"

# Phase 25 — 01e. Auth::TotpEnroller specs.
RSpec.describe Auth::TotpEnroller do
  let(:user) { create(:user) }

  describe ".call (happy path)" do
    subject(:result) { described_class.call(user: user) }

    it "returns a 32-char base32 seed" do
      seed = result[:seed]
      expect(seed).to be_a(String)
      expect(seed.length).to eq(described_class::SEED_LENGTH)
      expect(seed).to match(/\A[A-Z2-7]+\z/)
    end

    it "returns exactly 10 plaintext backup codes" do
      expect(result[:codes].length).to eq(described_class::BACKUP_CODE_COUNT)
    end

    it "uses the safe 28-char alphabet for backup codes (no O / I / L / B / 0 / 1 / 8)" do
      forbidden = %w[O I L B 0 1 8]
      result[:codes].each do |code|
        forbidden.each do |char|
          expect(code).not_to include(char), "code #{code} contains forbidden char #{char}"
        end
      end
    end

    it "persists the encrypted seed on the user row" do
      seed = result[:seed]
      expect(user.reload.totp_seed_encrypted).to eq(seed)
    end

    it "persists 10 backup code rows with bcrypt digests" do
      result
      expect(user.totp_backup_codes.count).to eq(10)
      user.totp_backup_codes.each do |row|
        expect(row.code_digest).to start_with("$2a$").or start_with("$2b$").or start_with("$2y$")
      end
    end

    it "every returned plaintext code matches its stored bcrypt digest" do
      result[:codes].each do |plaintext|
        row = user.totp_backup_codes.detect { |r| r.matches?(plaintext) }
        expect(row).not_to be_nil, "no digest row matched plaintext #{plaintext}"
      end
    end

    it "does NOT stamp totp_enabled_at (confirm step does)" do
      result
      expect(user.reload.totp_enabled_at).to be_nil
    end
  end

  describe ".call (re-enrollment after disable)" do
    it "replaces seed + codes when user is not currently enrolled" do
      user.update!(
        totp_seed_encrypted: nil,
        totp_disabled_at: 1.day.ago
      )
      user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("STALE234"))

      result = described_class.call(user: user)

      expect(user.reload.totp_seed_encrypted).to eq(result[:seed])
      # Stale code wiped; 10 fresh codes.
      expect(user.totp_backup_codes.count).to eq(10)
    end

    it "clears the totp_disabled_at stamp" do
      user.update!(totp_disabled_at: 1.day.ago)
      described_class.call(user: user)
      expect(user.reload.totp_disabled_at).to be_nil
    end
  end

  describe ".call (sad path)" do
    it "raises AlreadyEnrolled when the user is already enrolled" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: Time.current)
      expect {
        described_class.call(user: user)
      }.to raise_error(described_class::AlreadyEnrolled)
    end

    it "raises ArgumentError when user is nil" do
      expect { described_class.call(user: nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".call (flaw class)" do
    it "the returned seed decrypts back to the same plaintext stored at rest" do
      result = described_class.call(user: user)
      expect(user.reload.totp_seed_encrypted).to eq(result[:seed])
    end

    it "every backup code is exactly BACKUP_CODE_LENGTH chars" do
      result = described_class.call(user: user)
      result[:codes].each do |code|
        expect(code.length).to eq(described_class::BACKUP_CODE_LENGTH)
      end
    end
  end
end
