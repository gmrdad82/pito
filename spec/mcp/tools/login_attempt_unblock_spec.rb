require "rails_helper"
require_relative "../../../app/mcp/tools/login_attempt_unblock"

# Phase 25 — 01d. `login_attempt_unblock` MCP tool.
RSpec.describe Mcp::Tools::LoginAttemptUnblock do
  let(:fp)        { Digest::SHA256.hexdigest("unblock-fp") }
  let(:ip_prefix) { "10.99.0.0/24" }
  let!(:block_row) do
    create(:blocked_location,
           fingerprint_hash: fp,
           ip_prefix: ip_prefix,
           source_surface: :web)
  end

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path — by blocked_location_id" do
    it "stamps unblocked_at + writes an audit row" do
      result = nil
      expect {
        result = call_tool(blocked_location_id: block_row.id, confirm: "yes")
      }.to change { block_row.reload.unblocked_at }.from(nil)

      data = parse(result)
      expect(data["unblocked"]).to eq("yes")
      expect(data["already_unblocked"]).to eq("no")
      expect(data["blocked_location_id"]).to eq(block_row.id)
      expect(data["audit_log_id"]).to be_a(Integer)
    end

    it "writes the AuthAuditLog row with action: :unblock, source_surface: :mcp" do
      expect {
        call_tool(blocked_location_id: block_row.id, confirm: "yes")
      }.to change { AuthAuditLog.where(action: AuthAuditLog.actions[:unblock]).count }.by(1)

      row = AuthAuditLog.where(action: AuthAuditLog.actions[:unblock]).order(created_at: :desc).first
      expect(row.source_surface).to eq("mcp")
      expect(row.target_type).to eq("BlockedLocation")
      expect(row.target_id).to eq(block_row.id)
    end
  end

  describe "happy path — by (fingerprint, ip_prefix) pair" do
    it "finds the active row and unblocks it" do
      result = call_tool(fingerprint: fp, ip_prefix: ip_prefix, confirm: "yes")
      data = parse(result)

      expect(data["unblocked"]).to eq("yes")
      expect(data["blocked_location_id"]).to eq(block_row.id)
      expect(block_row.reload.unblocked_at).to be_present
    end
  end

  describe "two-step confirm (preview)" do
    it "missing confirm returns the preview shape with no state change" do
      expect {
        data = parse(call_tool(blocked_location_id: block_row.id))
        expect(data["preview"]).to be_a(Hash)
        expect(data["preview"]["blocked_location"]["id"]).to eq(block_row.id)
        expect(data["preview"]["side_effects"]["will_stamp_unblocked_at"]).to eq("yes")
        expect(data["next_step"]).to include("confirm: \"yes\"")
      }.not_to change { block_row.reload.unblocked_at }
    end

    it 'rejects confirm values outside yes/no' do
      result = call_tool(blocked_location_id: block_row.id, confirm: "true")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_input")
    end
  end

  describe "sad paths" do
    it "missing both selectors returns invalid_input" do
      result = call_tool(confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_input")
    end

    it "unknown blocked_location_id returns not_found" do
      result = call_tool(blocked_location_id: 999_999, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("not_found")
    end

    it "no active row for the supplied pair returns not_found" do
      block_row.update!(unblocked_at: Time.current, unblocked_by_user: create(:user))

      result = call_tool(fingerprint: fp, ip_prefix: ip_prefix, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("not_found")
    end
  end

  describe "edge: already-unblocked row by id (idempotent)" do
    it "returns already_unblocked: yes and writes no fresh audit row" do
      block_row.update!(unblocked_at: Time.current, unblocked_by_user: create(:user))

      expect {
        result = call_tool(blocked_location_id: block_row.id, confirm: "yes")
        data = parse(result)
        expect(data["unblocked"]).to eq("no")
        expect(data["already_unblocked"]).to eq("yes")
      }.not_to change { AuthAuditLog.where(action: AuthAuditLog.actions[:unblock]).count }
    end
  end

  describe "scope gate" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-unblock",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool(blocked_location_id: block_row.id, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
