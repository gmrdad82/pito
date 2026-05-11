require "rails_helper"

# Phase 25 — 01e. Auth::TotpDisabler specs.
RSpec.describe Auth::TotpDisabler do
  let(:user) { create(:user, :totp_enabled) }

  describe ".call (happy path)" do
    it "clears totp_seed_encrypted" do
      described_class.call(user: user)
      expect(user.reload.totp_seed_encrypted).to be_nil
    end

    it "stamps totp_disabled_at" do
      described_class.call(user: user)
      expect(user.reload.totp_disabled_at).to be_present
    end

    it "clears totp_enabled_at" do
      described_class.call(user: user)
      expect(user.reload.totp_enabled_at).to be_nil
    end

    it "destroys every backup code row" do
      expect { described_class.call(user: user) }.to change { user.totp_backup_codes.count }.to(0)
    end

    it "writes an AuthAuditLog row with action: totp_disable" do
      expect { described_class.call(user: user) }.to change {
        AuthAuditLog.where(action: AuthAuditLog.actions[:totp_disable]).count
      }.by(1)
    end

    it "is no-op when the user is not enrolled" do
      bare = create(:user)
      expect(described_class.call(user: bare)).to eq(:noop)
      expect(bare.reload.totp_disabled_at).to be_nil
    end

    it "raises on nil user" do
      expect { described_class.call(user: nil) }.to raise_error(ArgumentError)
    end
  end
end
