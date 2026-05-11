require "rails_helper"
require_relative "../../../app/mcp/tools/login_attempt_approve"

# Phase 25 — 01d. `login_attempt_approve` MCP tool.
RSpec.describe Mcp::Tools::LoginAttemptApprove do
  include ActiveSupport::Testing::TimeHelpers

  let(:target_user)     { create(:user) }
  let(:pending_session) { create(:session, :pending, user: target_user) }
  let!(:attempt) do
    create(:login_attempt, :pending,
           user: target_user,
           session: pending_session,
           email_attempted: target_user.email,
           fingerprint_hash: Digest::SHA256.hexdigest("approve-fp"),
           ip_prefix: "10.0.0.0/24")
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
    it "approves and returns the activated session_id" do
      result = call_tool(id: attempt.id, confirm: "yes")
      data = parse(result)

      expect(data["approved"]).to eq("yes")
      expect(data["attempt_id"]).to eq(attempt.id)
      expect(data["session_id"]).to eq(pending_session.id)
      expect(data["result"]).to eq("ok")

      expect(pending_session.reload.state_active?).to be true
    end

    it "writes an AuthAuditLog row with source_surface: :mcp, action: :approve" do
      expect {
        call_tool(id: attempt.id, confirm: "yes")
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.order(created_at: :desc).first
      expect(row.source_surface).to eq("mcp")
      expect(row.action).to eq("approve")
      expect(row.target_type).to eq("LoginAttempt")
      expect(row.target_id).to eq(attempt.id)
    end

    it "includes the audit_log_id in the response payload" do
      data = parse(call_tool(id: attempt.id, confirm: "yes"))
      expect(data["audit_log_id"]).to be_a(Integer)
      expect(AuthAuditLog.find(data["audit_log_id"]).action).to eq("approve")
    end
  end

  describe "two-step confirm (preview)" do
    it "missing confirm returns the preview shape with no state change" do
      expect {
        result = call_tool(id: attempt.id)
        data = parse(result)

        expect(data["preview"]).to be_a(Hash)
        expect(data["preview"]["attempt"]["id"]).to eq(attempt.id)
        expect(data["preview"]["side_effects"]["will_activate_session"]).to eq("yes")
        expect(data["next_step"]).to include("confirm: \"yes\"")
        expect(data["can_proceed"]).to eq("yes")
      }.not_to change { pending_session.reload.state }
    end

    it 'confirm: "no" returns the same preview shape with no state change' do
      expect {
        data = parse(call_tool(id: attempt.id, confirm: "no"))
        expect(data["preview"]).to be_a(Hash)
      }.not_to change { pending_session.reload.state }
    end

    it 'rejects confirm values outside yes/no with invalid_input' do
      result = call_tool(id: attempt.id, confirm: "true")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("invalid_input")
    end
  end

  describe "sad paths" do
    it "missing id returns invalid_input" do
      result = call_tool(confirm: "no")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("invalid_input")
    end

    it "unknown id returns not_found" do
      result = call_tool(id: 999_999, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("not_found")
    end

    it "pending window already elapsed returns expired" do
      travel_to(15.minutes.from_now) do
        result = call_tool(id: attempt.id, confirm: "yes")
        expect(result.to_h[:isError]).to be(true)
        payload = JSON.parse(result.content.first[:text])
        expect(payload["error"]).to eq("expired")
      end
    end

    it "already-approved (state already active) returns already_resolved" do
      pending_session.update!(state: :active, approval_required_until: nil)
      result = call_tool(id: attempt.id, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("already_resolved")
    end
  end

  describe "scope gate" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-approve",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool(id: attempt.id, confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
