require "rails_helper"

# Phase 25 — 01e. Auth::BackupCodeRegenerator specs.
RSpec.describe Auth::BackupCodeRegenerator do
  let(:user) { create(:user, :totp_enabled) }

  describe ".call (happy path)" do
    it "destroys existing backup codes" do
      existing_ids = user.totp_backup_codes.pluck(:id)
      described_class.call(user: user)
      remaining = user.totp_backup_codes.pluck(:id)
      expect(remaining & existing_ids).to be_empty
    end

    it "creates exactly 10 fresh codes" do
      described_class.call(user: user)
      expect(user.totp_backup_codes.count).to eq(10)
    end

    it "returns the 10 plaintext codes" do
      codes = described_class.call(user: user)
      expect(codes.length).to eq(10)
      codes.each { |code| expect(code.length).to eq(Auth::TotpEnroller::BACKUP_CODE_LENGTH) }
    end

    it "writes an AuthAuditLog row with action: backup_code_regenerate" do
      expect { described_class.call(user: user) }.to change {
        AuthAuditLog.where(action: AuthAuditLog.actions[:backup_code_regenerate]).count
      }.by(1)
    end
  end

  describe ".call (sad path)" do
    it "raises NotEnrolled when the user is not enrolled" do
      bare = create(:user)
      expect {
        described_class.call(user: bare)
      }.to raise_error(described_class::NotEnrolled)
    end

    it "raises ArgumentError on nil user" do
      expect { described_class.call(user: nil) }.to raise_error(ArgumentError)
    end
  end
end
