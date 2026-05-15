require "rails_helper"
require_relative "../../../app/mcp/tools/login_attempts_pending"

# Phase 25 — 01b. `login_attempts_pending` MCP read tool.
RSpec.describe Mcp::Tools::LoginAttemptsPending do
  let(:user) { create(:user) }
  let(:pending_session) { create(:session, :pending, user: user) }
  let(:expired_session) { create(:session, :expired_pending, user: user) }
  let!(:pending_attempt) do
    create(:login_attempt, :pending,
           user: user,
           session: pending_session,
           email_attempted: user.username)
  end
  let!(:expired_attempt) do
    # Attempt with result: pending_approval but whose session is past
    # its window — must NOT surface in the tool result.
    create(:login_attempt, :pending,
           user: user,
           session: expired_session,
           email_attempted: user.username)
  end

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy: returns only in-window pending rows" do
    it "includes the in-window pending attempt" do
      data = parse(call_tool)
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to include(pending_attempt.id)
    end

    it "excludes the pending-but-expired-window attempt" do
      data = parse(call_tool)
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).not_to include(expired_attempt.id)
    end
  end

  describe "boundary: yes/no booleans (LD-15)" do
    it "is_pending / is_expired / has_session all serialize as yes/no strings" do
      data = parse(call_tool)
      row = data["attempts"].first
      expect(%w[yes no]).to include(row["is_pending"])
      expect(%w[yes no]).to include(row["is_expired"])
      expect(%w[yes no]).to include(row["has_session"])
    end
  end

  describe "row shape" do
    it "carries the documented keys" do
      data = parse(call_tool)
      row = data["attempts"].first
      %w[id created_at result reason is_pending is_expired has_session
         expires_at ip ip_prefix geo browser os
         fingerprint_hash fingerprint_short user_id session_id email_attempted].each do |k|
        expect(row.keys).to include(k), "missing key #{k}"
      end
    end

    it "expires_at carries the session's approval_required_until ISO8601" do
      data = parse(call_tool)
      row = data["attempts"].find { |r| r["id"] == pending_attempt.id }
      expect(row["expires_at"]).to eq(pending_session.approval_required_until.utc.iso8601)
    end
  end

  describe "scope gate" do
    # Phase 25 — 01d. Swapped to the dedicated `auth` scope.
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-pending",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end

  describe "pagination" do
    it "respects per_page and reports total" do
      data = parse(call_tool(per_page: 1))
      expect(data["pagination"]).to include(
        "page" => 1, "per_page" => 1
      )
      expect(data["pagination"]["total"]).to be >= 1
    end
  end
end
