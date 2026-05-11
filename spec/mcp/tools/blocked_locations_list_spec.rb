require "rails_helper"
require_relative "../../../app/mcp/tools/blocked_locations_list"

RSpec.describe Mcp::Tools::BlockedLocationsList do
  include ActiveSupport::Testing::TimeHelpers

  let!(:web_block) do
    travel_to(2.hours.ago) do
      create(:blocked_location, source_surface: :web,
                                fingerprint_hash: "a" * 64,
                                ip_prefix: "1.1.1.0/24")
    end
  end
  let!(:tui_block) do
    travel_to(1.hour.ago) do
      create(:blocked_location, source_surface: :tui,
                                fingerprint_hash: "b" * 64,
                                ip_prefix: "2.2.2.0/24")
    end
  end
  let!(:unblocked) do
    create(:blocked_location, :unblocked, source_surface: :mcp,
                                          fingerprint_hash: "c" * 64,
                                          ip_prefix: "3.3.3.0/24")
  end

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path" do
    it "returns rows sorted desc by blocked_at" do
      data = parse(call_tool)
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids.first).to eq(unblocked.id)
      expect(ids.last).to eq(web_block.id)
    end

    it "carries the documented keys on each row" do
      data = parse(call_tool)
      keys = data["blocks"].first.keys
      %w[id blocked_at source_surface blocked_by_user_id
         unblocked_at unblocked_by_user_id is_active
         fingerprint_hash fingerprint_short ip_prefix
         attempt_count last_attempt_at reason].each do |k|
        expect(keys).to include(k), "missing key #{k}"
      end
    end

    it "is_active is yes / no (LD-15 boundary)" do
      data = parse(call_tool)
      data["blocks"].each do |row|
        expect(%w[yes no]).to include(row["is_active"])
      end
    end

    it "reports pagination" do
      data = parse(call_tool(per_page: 2))
      expect(data["pagination"]).to include(
        "page" => 1, "per_page" => 2, "total" => 3
      )
    end

    it "fingerprint_short is the first 12 hex characters" do
      data = parse(call_tool(fingerprint: "a" * 64))
      expect(data["blocks"].first["fingerprint_short"]).to eq("a" * 12)
    end
  end

  describe "filters" do
    it "filters by source_surface" do
      data = parse(call_tool(source_surface: "tui"))
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids).to contain_exactly(tui_block.id)
    end

    it "filters by active=yes (active rows only)" do
      data = parse(call_tool(active: "yes"))
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids).to include(web_block.id, tui_block.id)
      expect(ids).not_to include(unblocked.id)
    end

    it "filters by active=no (soft-unblocked rows only)" do
      data = parse(call_tool(active: "no"))
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids).to contain_exactly(unblocked.id)
    end

    it "filters by fingerprint" do
      data = parse(call_tool(fingerprint: "b" * 64))
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids).to contain_exactly(tui_block.id)
    end

    it "filters by ip_prefix" do
      data = parse(call_tool(ip_prefix: "1.1.1.0/24"))
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids).to contain_exactly(web_block.id)
    end

    it "filters by since" do
      data = parse(call_tool(since: 30.minutes.ago.iso8601))
      ids = data["blocks"].map { |r| r["id"] }
      expect(ids).to contain_exactly(unblocked.id)
    end

    it "returns an error envelope on a malformed since" do
      result = call_tool(since: "garbage")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("invalid_filter")
    end

    it "returns an error envelope on a malformed until_ts" do
      result = call_tool(until_ts: "garbage")
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "scope gate" do
    # Phase 25 — 01d. Swapped from the temporary `app` placeholder to
    # the dedicated `auth` scope. A token holding only `app` (not `auth`)
    # must now be rejected.
    it "rejects callers without the auth scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-auth",
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

  describe "edge cases" do
    it "returns an empty array when no rows match" do
      data = parse(call_tool(fingerprint: "z" * 64))
      expect(data["blocks"]).to eq([])
      expect(data["pagination"]["total"]).to eq(0)
    end

    it "clamps per_page to the cap" do
      data = parse(call_tool(per_page: 999))
      expect(data["pagination"]["per_page"]).to eq(described_class::MAX_PER_PAGE)
    end
  end
end
