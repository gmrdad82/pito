require "rails_helper"
require_relative "../../../app/mcp/tools/login_attempts_list"

# Phase 25 — 01a + 01d. `login_attempts_list` MCP tool.
#
# 01d expanded the filter set (`until_ts`, `user_email`), swapped the
# scope gate from `app` to `auth`, and changed the bad-input contract
# from "silently widen the result set" to "return an `invalid_filter`
# error". This spec covers both the original scaffold paths and the
# new contract.
RSpec.describe Mcp::Tools::LoginAttemptsList do
  include ActiveSupport::Testing::TimeHelpers

  let!(:older) { travel_to(2.hours.ago) { create(:login_attempt) } }
  let!(:succ)  { create(:login_attempt, :success, :with_geo) }
  let!(:blocked) { create(:login_attempt, :blocked, ip: "9.9.9.9", ip_prefix: "9.9.9.0/24") }

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path" do
    it "returns rows sorted desc by created_at" do
      data = parse(call_tool)
      expect(data["attempts"]).to be_an(Array)
      expect(data["attempts"].first["id"]).to eq(blocked.id).or eq(succ.id)
      # Older row trails the recents.
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids.last).to eq(older.id)
    end

    it "carries yes/no Booleans at the boundary (LD-15)" do
      data = parse(call_tool)
      data["attempts"].each do |row|
        expect(%w[yes no]).to include(row["is_success"])
        expect(%w[yes no]).to include(row["is_failed"])
        expect(%w[yes no]).to include(row["is_blocked"])
      end
    end

    it "rows carry the documented keys" do
      data = parse(call_tool)
      keys = data["attempts"].first.keys
      %w[id created_at result reason is_success is_failed is_blocked
         ip ip_prefix geo browser os
         fingerprint_hash fingerprint_short user_id email_attempted].each do |k|
        expect(keys).to include(k), "missing key #{k}"
      end
    end

    it "pagination block reports page / per_page / total" do
      data = parse(call_tool(per_page: 2))
      expect(data["pagination"]).to include(
        "page" => 1, "per_page" => 2, "total" => 3
      )
    end
  end

  describe "scope gate (auth — Phase 25 — 01d)" do
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth-list",
        scopes: [ Scopes::APP ]
      ).first

      result = call_tool
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end

    it "rejects when there is no token at all" do
      Current.token = nil
      result = call_tool
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "filters — happy" do
    it "result=success returns only success rows" do
      data = parse(call_tool(result: "success"))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to contain_exactly(succ.id)
    end

    it "since narrows to recent rows" do
      data = parse(call_tool(since: 1.hour.ago.iso8601))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).not_to include(older.id)
    end

    it "until_ts narrows to older rows (Phase 25 — 01d)" do
      data = parse(call_tool(until_ts: 1.hour.ago.iso8601))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to contain_exactly(older.id)
    end

    it "ip filter applies exact match" do
      data = parse(call_tool(ip: "9.9.9.9"))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to contain_exactly(blocked.id)
    end

    it "fingerprint filter applies exact match" do
      data = parse(call_tool(fingerprint: blocked.fingerprint_hash))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to contain_exactly(blocked.id)
    end

    it "user_email filter applies exact match (Phase 25 — 01d)" do
      special = create(:login_attempt, email_attempted: "needle@example.test")
      data = parse(call_tool(user_email: "needle@example.test"))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to contain_exactly(special.id)
    end

    it "combined result + since + ip intersects correctly" do
      target = create(:login_attempt, :blocked,
                      ip: "9.9.9.9", ip_prefix: "9.9.9.0/24",
                      created_at: 30.minutes.ago)
      data = parse(call_tool(result: "blocked", since: 1.hour.ago.iso8601, ip: "9.9.9.9"))
      ids = data["attempts"].map { |r| r["id"] }
      expect(ids).to include(target.id, blocked.id)
      expect(ids).not_to include(older.id, succ.id)
    end
  end

  describe "filters — sad (invalid input rejected, Phase 25 — 01d)" do
    it "invalid result enum returns invalid_filter error" do
      result = call_tool(result: "not-a-result")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("invalid_filter")
      expect(payload["message"]).to include("invalid result")
    end

    it "invalid since timestamp returns invalid_filter error" do
      result = call_tool(since: "not-iso")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("invalid_filter")
      expect(payload["message"]).to include("since")
    end

    it "invalid until_ts timestamp returns invalid_filter error" do
      result = call_tool(until_ts: "garbage")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("invalid_filter")
      expect(payload["message"]).to include("until_ts")
    end
  end

  describe "pagination" do
    it "respects per_page cap" do
      data = parse(call_tool(per_page: 1, page: 1))
      expect(data["attempts"].size).to eq(1)
      expect(data["pagination"]["page"]).to eq(1)
    end

    it "page 2 returns the next slice" do
      data1 = parse(call_tool(per_page: 1, page: 1))
      data2 = parse(call_tool(per_page: 1, page: 2))
      expect(data1["attempts"].first["id"]).not_to eq(data2["attempts"].first["id"])
    end

    it "clamps per_page above the cap (100)" do
      data = parse(call_tool(per_page: 1_000))
      expect(data["pagination"]["per_page"]).to eq(100)
    end
  end
end
