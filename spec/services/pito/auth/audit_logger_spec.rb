require "rails_helper"

# AuditLogger service. Post-Phase-25 rollback: the location-tied
# vocabulary (approve / block / unblock / purge) is gone with the
# new-location approval surface. The active allowlist covers TOTP
# lifecycle + Voyage credential writes + password reset; the
# canonical target type is `User` (TOTP / password reset) or
# `AppSetting` (Voyage credential rotation).
RSpec.describe Pito::Auth::AuditLogger do
  let(:user) { create(:user) }

  describe ".call (happy)" do
    it "writes a row with the right shape" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :totp_enroll,
          target: user,
          metadata: { "note" => "ok" }
        )
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.last
      expect(row.acting_user_id).to eq(user.id)
      expect(row.source_surface).to eq("web")
      expect(row.action).to eq("totp_enroll")
      expect(row.target_type).to eq("User")
      expect(row.target_id).to eq(user.id)
      expect(row.metadata).to eq("note" => "ok")
    end

    it "accepts explicit target_type + target_id (no AR record)" do
      row = described_class.call(
        acting_user: user,
        source_surface: :mcp,
        action: :totp_disable,
        target_type: "User",
        target_id: 12345,
        metadata: {}
      )
      expect(row.target_type).to eq("User")
      expect(row.target_id).to eq(12345)
    end

    it "stringifies metadata keys" do
      row = described_class.call(
        acting_user: user,
        source_surface: :web,
        action: :totp_enroll,
        target: user,
        metadata: { ip: "1.2.3.4", session_id: 42 }
      )
      expect(row.metadata).to eq("ip" => "1.2.3.4", "session_id" => 42)
    end

    it "defaults metadata to {} when nil" do
      row = described_class.call(
        acting_user: user,
        source_surface: :web,
        action: :totp_enroll,
        target: user,
        metadata: nil
      )
      expect(row.metadata).to eq({})
    end

    it "accepts every action in the active allowlist" do
      %i[totp_enroll totp_disable backup_code_regenerate
         voyage_credentials_updated password_reset].each do |action|
        expect {
          described_class.call(
            acting_user: user,
            source_surface: :web,
            action: action,
            target: user
          )
        }.to change(AuthAuditLog, :count).by(1)
      end
    end

    it "accepts every source_surface in the LD-13 vocabulary" do
      %i[web tui mcp].each do |surface|
        expect {
          described_class.call(
            acting_user: user,
            source_surface: surface,
            action: :totp_enroll,
            target: user
          )
        }.to change(AuthAuditLog, :count).by(1)
      end
    end

    # The retired location-action vocabulary stays RESERVED in the
    # enum but the logger refuses to write the symbols.
    it "rejects the retired location-tied actions" do
      %i[approve block unblock purge youtube_credentials_updated].each do |action|
        expect {
          described_class.call(
            acting_user: user,
            source_surface: :web,
            action: action,
            target: user
          )
        }.to raise_error(ArgumentError, /invalid action/)
      end
    end
  end

  describe ".call (sad)" do
    it "raises on missing acting_user" do
      expect {
        described_class.call(
          acting_user: nil,
          source_surface: :web,
          action: :totp_enroll,
          target: user
        )
      }.to raise_error(ArgumentError, /acting_user required/)
    end

    it "raises when acting_user is not persisted" do
      expect {
        described_class.call(
          acting_user: User.new,
          source_surface: :web,
          action: :totp_enroll,
          target: user
        )
      }.to raise_error(ArgumentError, /acting_user must persist/)
    end

    it "raises on invalid source_surface" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :sms,
          action: :totp_enroll,
          target: user
        )
      }.to raise_error(ArgumentError, /invalid source_surface/)
    end

    it "raises on invalid action" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :destroy_universe,
          target: user
        )
      }.to raise_error(ArgumentError, /invalid action/)
    end

    it "raises when neither target nor (target_type + target_id) are supplied" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :totp_enroll
        )
      }.to raise_error(ArgumentError, /target/)
    end

    it "raises when target_type is given but target_id is missing" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :totp_enroll,
          target_type: "User"
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe "transaction posture (flaw: row must persist when caller commits)" do
    it "writes the row inside the caller's transaction (no inner BEGIN)" do
      # The service must NOT open its own transaction so callers can
      # wrap their domain mutation + audit in a single transaction.
      ActiveRecord::Base.transaction do
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :totp_enroll,
          target: user
        )
        raise ActiveRecord::Rollback
      end

      expect(AuthAuditLog.count).to eq(0)
    end
  end
end
