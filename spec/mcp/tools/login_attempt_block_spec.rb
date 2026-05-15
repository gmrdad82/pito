require "rails_helper"
require_relative "../../../app/mcp/tools/login_attempt_block"

# Phase 25 — 01d. `login_attempt_block` MCP tool.
RSpec.describe Mcp::Tools::LoginAttemptBlock do
  include ActiveSupport::Testing::TimeHelpers

  let(:target_user)     { create(:user) }
  let(:pending_session) { create(:session, :pending, user: target_user) }
  let!(:attempt) do
    create(:login_attempt, :pending,
           user: target_user,
           session: pending_session,
           email_attempted: target_user.username,
           fingerprint_hash: Digest::SHA256.hexdigest("block-fp-mcp"),
           ip_prefix: "172.16.0.0/24")
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path (confirm: yes)" do
    it "creates a BlockedLocation, revokes the session, returns ok" do
      result = nil
      expect {
        result = call_tool(id: attempt.id, confirm: "yes")
      }.to change(BlockedLocation, :count).by(1)

      data = parse(result)
      expect(data["blocked"]).to eq("yes")
      expect(data["attempt_id"]).to eq(attempt.id)
      expect(data["blocked_location_id"]).to be_a(Integer)
      expect(data["revoked_session_id"]).to eq(pending_session.id)
      expect(data["result"]).to eq("ok")

      expect(pending_session.reload.state_revoked?).to be true
    end

    it "writes an AuthAuditLog row with source_surface: :mcp, action: :block" do
      expect {
        call_tool(id: attempt.id, confirm: "yes")
      }.to change { AuthAuditLog.where(action: AuthAuditLog.actions[:block]).count }.by(1)

      row = AuthAuditLog.where(action: AuthAuditLog.actions[:block]).order(created_at: :desc).first
      expect(row.source_surface).to eq("mcp")
      expect(row.target_type).to eq("LoginAttempt")
      expect(row.target_id).to eq(attempt.id)
    end

    it "stamps a fresh LoginAttempt with reason: :blocked_from_mcp" do
      call_tool(id: attempt.id, confirm: "yes")
      blocked_row = LoginAttempt.where(result: :blocked).order(created_at: :desc).first
      expect(blocked_row.reason).to eq("blocked_from_mcp")
    end
  end

  describe "two-step confirm (preview)" do
    it "missing confirm returns the preview shape with no state change" do
      expect {
        data = parse(call_tool(id: attempt.id))

        expect(data["preview"]).to be_a(Hash)
        expect(data["preview"]["attempt"]["id"]).to eq(attempt.id)
        expect(data["preview"]["side_effects"]["will_create_blocked_location"]).to eq("yes")
        expect(data["preview"]["side_effects"]["will_revoke_session"]).to eq("yes")
        expect(data["next_step"]).to include("confirm: \"yes\"")
        expect(data["can_proceed"]).to eq("yes")
      }.not_to change(BlockedLocation, :count)
    end

    it 'confirm: "no" returns the preview shape with no state change' do
      expect {
        call_tool(id: attempt.id, confirm: "no")
      }.not_to change(BlockedLocation, :count)
    end
  end

  describe "edge: pair already blocked" do
    it "does NOT create a duplicate BlockedLocation row" do
      create(:blocked_location,
             fingerprint_hash: attempt.fingerprint_hash,
             ip_prefix: attempt.ip_prefix)

      expect {
        call_tool(id: attempt.id, confirm: "yes")
      }.not_to change(BlockedLocation, :count)
    end

    it "still audit-logs the operator action" do
      create(:blocked_location,
             fingerprint_hash: attempt.fingerprint_hash,
             ip_prefix: attempt.ip_prefix)

      expect {
        call_tool(id: attempt.id, confirm: "yes")
      }.to change { AuthAuditLog.where(action: AuthAuditLog.actions[:block]).count }.by(1)
    end

    it "the preview surfaces already_blocked: yes and will_create_blocked_location: no" do
      create(:blocked_location,
             fingerprint_hash: attempt.fingerprint_hash,
             ip_prefix: attempt.ip_prefix)

      data = parse(call_tool(id: attempt.id))
      expect(data["preview"]["already_blocked"]).to eq("yes")
      expect(data["preview"]["side_effects"]["will_create_blocked_location"]).to eq("no")
    end
  end

  describe "sad paths" do
    it "missing id returns invalid_input" do
      result = call_tool(confirm: "no")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_input")
    end

    it "unknown id returns not_found" do
      result = call_tool(id: 999_999, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("not_found")
    end

    it "already-resolved session returns already_resolved" do
      pending_session.update!(state: :active, approval_required_until: nil)
      result = call_tool(id: attempt.id, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("already_resolved")
    end

    it "elapsed window returns expired" do
      travel_to(15.minutes.from_now) do
        result = call_tool(id: attempt.id, confirm: "yes")
        expect(result.to_h[:isError]).to be(true)
        expect(JSON.parse(result.content.first[:text])["error"]).to eq("expired")
      end
    end
  end

  describe "scope gate" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-block",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool(id: attempt.id, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
