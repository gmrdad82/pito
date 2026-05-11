require "rails_helper"
require_relative "../../../app/mcp/tools/login_attempt_purge"

# Phase 25 — 01d. `login_attempt_purge` MCP tool.
RSpec.describe Mcp::Tools::LoginAttemptPurge do
  include ActiveSupport::Testing::TimeHelpers

  let!(:failed_row)  { create(:login_attempt) } # default :failed
  let!(:blocked_row) { create(:login_attempt, :blocked) }
  let!(:success_row) { create(:login_attempt, :success) }

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path (confirm: yes)" do
    it "deletes rows matching the filter and reports the count" do
      expect {
        data = parse(call_tool(result: "failed", confirm: "yes"))
        expect(data["purged"]).to eq("yes")
        expect(data["deleted_count"]).to eq(1)
        expect(data["filter"]["result"]).to eq("failed")
      }.to change { LoginAttempt.exists?(id: failed_row.id) }.from(true).to(false)

      expect(LoginAttempt.exists?(id: blocked_row.id)).to be(true)
      expect(LoginAttempt.exists?(id: success_row.id)).to be(true)
    end

    it "writes an AuthAuditLog row with metadata: { filter, deleted_count }" do
      expect {
        call_tool(result: "failed", confirm: "yes")
      }.to change { AuthAuditLog.where(action: AuthAuditLog.actions[:purge]).count }.by(1)

      row = AuthAuditLog.where(action: AuthAuditLog.actions[:purge]).order(created_at: :desc).first
      expect(row.source_surface).to eq("mcp")
      expect(row.metadata["scope"]).to eq("login_attempts")
      expect(row.metadata["deleted_count"]).to eq(1)
      expect(row.metadata["filter"]["result"]).to eq("failed")
    end

    it "supports a time-window filter" do
      old = travel_to(3.days.ago) { create(:login_attempt) }
      data = parse(call_tool(
        result: "failed",
        since: 4.days.ago.iso8601,
        until_ts: 2.days.ago.iso8601,
        confirm: "yes"
      ))
      expect(data["deleted_count"]).to eq(1)
      expect(LoginAttempt.exists?(id: old.id)).to be(false)
      expect(LoginAttempt.exists?(id: failed_row.id)).to be(true)
    end
  end

  describe "safety: empty filter rejected" do
    it "no filter at all + confirm: yes returns invalid_input" do
      expect {
        result = call_tool(confirm: "yes")
        expect(result.to_h[:isError]).to be(true)
        payload = JSON.parse(result.content.first[:text])
        expect(payload["error"]).to eq("invalid_input")
        expect(payload["message"]).to include("at least one filter")
      }.not_to change(LoginAttempt, :count)
    end

    it "no filter + confirm: no also rejects (no preview path for empty filter)" do
      result = call_tool(confirm: "no")
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "two-step confirm (preview)" do
    it "missing confirm returns a preview with the prospective row count" do
      expect {
        data = parse(call_tool(result: "failed"))
        expect(data["preview"]["filter"]["result"]).to eq("failed")
        expect(data["preview"]["prospective_deleted_count"]).to eq(1)
        expect(data["preview"]["side_effects"]["will_delete_login_attempt_rows"]).to eq("yes")
        expect(data["next_step"]).to include("confirm: \"yes\"")
      }.not_to change(LoginAttempt, :count)
    end

    it 'confirm: "no" returns the preview without deleting' do
      expect {
        data = parse(call_tool(result: "failed", confirm: "no"))
        expect(data["preview"]).to be_a(Hash)
      }.not_to change(LoginAttempt, :count)
    end

    it 'rejects confirm values outside yes/no' do
      result = call_tool(result: "failed", confirm: "true")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_input")
    end

    it "preview with prospective_count: 0 marks will_delete: no" do
      data = parse(call_tool(result: "rate_limited"))
      expect(data["preview"]["prospective_deleted_count"]).to eq(0)
      expect(data["preview"]["side_effects"]["will_delete_login_attempt_rows"]).to eq("no")
    end
  end

  describe "sad paths" do
    it "invalid since timestamp returns invalid_filter" do
      result = call_tool(since: "not-iso", confirm: "no")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_filter")
    end
  end

  describe "scope gate" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-purge",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool(result: "failed", confirm: "yes")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
