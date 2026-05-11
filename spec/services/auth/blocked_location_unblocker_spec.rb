require "rails_helper"

# Phase 25 — 01d. BlockedLocationUnblocker service.
RSpec.describe Auth::BlockedLocationUnblocker do
  let(:actor) { create(:user) }
  let(:fp)        { Digest::SHA256.hexdigest("svc-unblock-fp") }
  let(:ip_prefix) { "10.77.0.0/24" }
  let!(:row) do
    create(:blocked_location,
           fingerprint_hash: fp,
           ip_prefix: ip_prefix,
           source_surface: :web)
  end

  describe ".call — happy path by row" do
    it "stamps unblocked_at + unblocked_by_user_id" do
      described_class.call(
        blocked_location: row,
        acting_user: actor,
        source: :mcp
      )

      row.reload
      expect(row.unblocked_at).to be_present
      expect(row.unblocked_by_user_id).to eq(actor.id)
    end

    it "writes an AuthAuditLog row with action: :unblock, source_surface: :mcp" do
      expect {
        described_class.call(
          blocked_location: row,
          acting_user: actor,
          source: :mcp
        )
      }.to change { AuthAuditLog.where(action: AuthAuditLog.actions[:unblock]).count }.by(1)

      audit = AuthAuditLog.where(action: AuthAuditLog.actions[:unblock]).order(created_at: :desc).first
      expect(audit.source_surface).to eq("mcp")
      expect(audit.target_type).to eq("BlockedLocation")
      expect(audit.target_id).to eq(row.id)
      expect(audit.metadata["ip_prefix"]).to eq(ip_prefix)
    end

    it "returns the row + already_unblocked: false" do
      result = described_class.call(
        blocked_location: row,
        acting_user: actor,
        source: :mcp
      )
      expect(result[:blocked_location].id).to eq(row.id)
      expect(result[:already_unblocked]).to be(false)
    end
  end

  describe ".call — happy path by pair" do
    it "looks up the active matching row" do
      result = described_class.call(
        fingerprint_hash: fp,
        ip_prefix: ip_prefix,
        acting_user: actor,
        source: :web
      )
      expect(result[:blocked_location].id).to eq(row.id)
      expect(row.reload.unblocked_at).to be_present
    end
  end

  describe "edge: already unblocked (idempotent)" do
    it "returns the row with already_unblocked: true and writes no audit row" do
      row.update!(unblocked_at: 1.hour.ago, unblocked_by_user: actor)

      expect {
        result = described_class.call(
          blocked_location: row,
          acting_user: actor,
          source: :mcp
        )
        expect(result[:already_unblocked]).to be(true)
      }.not_to change { AuthAuditLog.where(action: AuthAuditLog.actions[:unblock]).count }
    end
  end

  describe "sad paths" do
    it "no matching pair raises NotBlocked" do
      expect {
        described_class.call(
          fingerprint_hash: "0" * 64,
          ip_prefix: "192.168.99.0/24",
          acting_user: actor,
          source: :mcp
        )
      }.to raise_error(Auth::BlockedLocationUnblocker::NotBlocked)
    end

    it "supplied row that no longer exists raises NotBlocked" do
      ghost_id = row.id
      row.destroy!
      ghost = BlockedLocation.new(id: ghost_id)

      expect {
        described_class.call(
          blocked_location: ghost,
          acting_user: actor,
          source: :mcp
        )
      }.to raise_error(Auth::BlockedLocationUnblocker::NotBlocked)
    end

    it "missing acting_user raises ArgumentError" do
      expect {
        described_class.call(
          blocked_location: row,
          acting_user: nil,
          source: :mcp
        )
      }.to raise_error(ArgumentError)
    end

    it "invalid source raises ArgumentError" do
      expect {
        described_class.call(
          blocked_location: row,
          acting_user: actor,
          source: :bogus
        )
      }.to raise_error(ArgumentError)
    end

    it "missing both row and pair raises ArgumentError" do
      expect {
        described_class.call(
          acting_user: actor,
          source: :mcp
        )
      }.to raise_error(ArgumentError)
    end
  end
end
