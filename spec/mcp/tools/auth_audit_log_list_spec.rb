require "rails_helper"
require_relative "../../../app/mcp/tools/auth_audit_log_list"

# Phase 25 — 01d. `auth_audit_log_list` MCP read tool.
RSpec.describe Mcp::Tools::AuthAuditLogList do
  include ActiveSupport::Testing::TimeHelpers

  let(:actor) { create(:user) }
  let!(:approve_row) do
    travel_to(2.hours.ago) do
      create(:auth_audit_log,
             acting_user: actor,
             source_surface: :mcp,
             action: :approve,
             target_type: "LoginAttempt",
             target_id: 42)
    end
  end
  let!(:block_row) do
    create(:auth_audit_log,
           acting_user: actor,
           source_surface: :web,
           action: :block,
           target_type: "LoginAttempt",
           target_id: 43)
  end
  let!(:older_row) do
    travel_to(30.days.ago) do
      create(:auth_audit_log,
             acting_user: actor,
             source_surface: :tui,
             action: :purge,
             target_type: "User",
             target_id: actor.id)
    end
  end

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path" do
    it "returns rows sorted desc by created_at" do
      data = parse(call_tool)
      ids = data["rows"].map { |r| r["id"] }
      expect(ids.first).to eq(block_row.id)
      expect(ids.last).to eq(older_row.id)
    end

    it "rows carry the documented keys + yes/no Boolean (is_recent)" do
      data = parse(call_tool)
      row = data["rows"].first
      %w[id created_at action source_surface acting_user_id
         target_type target_id metadata is_recent].each do |k|
        expect(row.keys).to include(k), "missing key #{k}"
      end
      expect(%w[yes no]).to include(row["is_recent"])
    end

    it "pagination block reports page / per_page / total" do
      data = parse(call_tool(per_page: 2))
      expect(data["pagination"]["page"]).to eq(1)
      expect(data["pagination"]["per_page"]).to eq(2)
      expect(data["pagination"]["total"]).to eq(3)
    end
  end

  describe "filters" do
    it "action filter narrows to matching rows" do
      data = parse(call_tool(action: "approve"))
      ids = data["rows"].map { |r| r["id"] }
      expect(ids).to contain_exactly(approve_row.id)
    end

    it "source_surface filter narrows to matching rows" do
      data = parse(call_tool(source_surface: "mcp"))
      ids = data["rows"].map { |r| r["id"] }
      expect(ids).to contain_exactly(approve_row.id)
    end

    it "since narrows to recent rows" do
      data = parse(call_tool(since: 1.day.ago.iso8601))
      ids = data["rows"].map { |r| r["id"] }
      expect(ids).not_to include(older_row.id)
    end

    it "acting_user_email exact-match joins via the User table" do
      other = create(:user)
      mine = create(:auth_audit_log, acting_user: other,
                                     action: :totp_enroll, target_type: "User", target_id: other.id)
      data = parse(call_tool(acting_user_email: other.email))
      ids = data["rows"].map { |r| r["id"] }
      expect(ids).to contain_exactly(mine.id)
    end

    it "unknown acting_user_email returns empty rows (no error)" do
      data = parse(call_tool(acting_user_email: "nobody@example.test"))
      expect(data["rows"]).to eq([])
      expect(data["pagination"]["total"]).to eq(0)
    end

    it "target_type + target_id intersect correctly" do
      data = parse(call_tool(target_type: "LoginAttempt", target_id: 42))
      ids = data["rows"].map { |r| r["id"] }
      expect(ids).to contain_exactly(approve_row.id)
    end
  end

  describe "sad paths" do
    it "invalid action returns invalid_filter" do
      result = call_tool(action: "not-a-thing")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_filter")
    end

    it "invalid source_surface returns invalid_filter" do
      result = call_tool(source_surface: "smoke")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_filter")
    end

    it "invalid since timestamp returns invalid_filter" do
      result = call_tool(since: "garbage")
      expect(result.to_h[:isError]).to be(true)
      expect(JSON.parse(result.content.first[:text])["error"]).to eq("invalid_filter")
    end
  end

  describe "scope gate" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-audit",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
