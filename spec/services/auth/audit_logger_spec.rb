require "rails_helper"

# Phase 25 — 01c (LD-13). AuditLogger service.
RSpec.describe Auth::AuditLogger do
  let(:user) { create(:user) }
  let(:attempt) { create(:login_attempt, :pending, user: user) }

  describe ".call (happy)" do
    it "writes a row with the right shape" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :approve,
          target: attempt,
          metadata: { "note" => "ok" }
        )
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.last
      expect(row.acting_user_id).to eq(user.id)
      expect(row.source_surface).to eq("web")
      expect(row.action).to eq("approve")
      expect(row.target_type).to eq("LoginAttempt")
      expect(row.target_id).to eq(attempt.id)
      expect(row.metadata).to eq("note" => "ok")
    end

    it "accepts explicit target_type + target_id (no AR record)" do
      row = described_class.call(
        acting_user: user,
        source_surface: :mcp,
        action: :block,
        target_type: "LoginAttempt",
        target_id: 12345,
        metadata: {}
      )
      expect(row.target_type).to eq("LoginAttempt")
      expect(row.target_id).to eq(12345)
    end

    it "stringifies metadata keys" do
      row = described_class.call(
        acting_user: user,
        source_surface: :web,
        action: :approve,
        target: attempt,
        metadata: { ip: "1.2.3.4", session_id: 42 }
      )
      expect(row.metadata).to eq("ip" => "1.2.3.4", "session_id" => 42)
    end

    it "defaults metadata to {} when nil" do
      row = described_class.call(
        acting_user: user,
        source_surface: :web,
        action: :approve,
        target: attempt,
        metadata: nil
      )
      expect(row.metadata).to eq({})
    end

    # Phase 29 — Unit A1. `youtube_credentials_updated` was dropped from
    # `Auth::AuditLogger`'s active allowlist (the YouTube credentials
    # Settings pane is gone). The `AuthAuditLog` enum value 7 stays
    # reserved, but the logger refuses to write that action — see the
    # dedicated example below.
    it "accepts every action in the active allowlist" do
      %i[approve block unblock purge
         totp_enroll totp_disable backup_code_regenerate
         voyage_credentials_updated].each do |action|
        expect {
          described_class.call(
            acting_user: user,
            source_surface: :web,
            action: action,
            target: attempt
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
            action: :approve,
            target: attempt
          )
        }.to change(AuthAuditLog, :count).by(1)
      end
    end

    # Phase 29 — Unit A1. `youtube_credentials_updated` is no longer in
    # the active allowlist — the logger rejects it even though the
    # underlying `AuthAuditLog` enum value 7 stays reserved.
    it "rejects the retired youtube_credentials_updated action" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :youtube_credentials_updated,
          target: attempt
        )
      }.to raise_error(ArgumentError, /invalid action/)
    end
  end

  describe ".call (sad)" do
    it "raises on missing acting_user" do
      expect {
        described_class.call(
          acting_user: nil,
          source_surface: :web,
          action: :approve,
          target: attempt
        )
      }.to raise_error(ArgumentError, /acting_user required/)
    end

    it "raises when acting_user is not persisted" do
      expect {
        described_class.call(
          acting_user: User.new,
          source_surface: :web,
          action: :approve,
          target: attempt
        )
      }.to raise_error(ArgumentError, /acting_user must persist/)
    end

    it "raises on invalid source_surface" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :sms,
          action: :approve,
          target: attempt
        )
      }.to raise_error(ArgumentError, /invalid source_surface/)
    end

    it "raises on invalid action" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :destroy_universe,
          target: attempt
        )
      }.to raise_error(ArgumentError, /invalid action/)
    end

    it "raises when neither target nor (target_type + target_id) are supplied" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :approve
        )
      }.to raise_error(ArgumentError, /target/)
    end

    it "raises when target_type is given but target_id is missing" do
      expect {
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :approve,
          target_type: "LoginAttempt"
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe "transaction posture (flaw: row must persist when caller commits)" do
    it "writes the row inside the caller's transaction (no inner BEGIN)" do
      # The service must NOT open its own transaction so callers can
      # wrap approve/block + audit in a single transaction.
      ActiveRecord::Base.transaction do
        described_class.call(
          acting_user: user,
          source_surface: :web,
          action: :approve,
          target: attempt
        )
        raise ActiveRecord::Rollback
      end

      expect(AuthAuditLog.count).to eq(0)
    end
  end
end
