require "rails_helper"
require_relative "../../../app/mcp/tools/notifications_list"

RSpec.describe Mcp::Tools::NotificationsList do
  include ActiveSupport::Testing::TimeHelpers

  let!(:unread_video) do
    travel_to(2.hours.ago) { create(:notification, :video_published) }
  end
  let!(:unread_sync_error) do
    travel_to(1.hour.ago) { create(:notification, :sync_error) }
  end
  let!(:read_calendar) do
    travel_to(3.hours.ago) { create(:notification, :read, :calendar_entry_firing) }
  end

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path (app scope)" do
    it "returns paginated rows" do
      data = parse(call_tool)
      expect(data["notifications"]).to be_a(Array)
      expect(data["notifications"].size).to eq(3)
      expect(data["pagination"]).to include(
        "page" => 1,
        "per_page" => 25,
        "total" => 3
      )
    end

    it "rows include `read` as a yes/no string (boundary discipline)" do
      data = parse(call_tool)
      data["notifications"].each do |row|
        expect(%w[yes no]).to include(row["read"])
      end
    end

    it "rows match NotificationFormatter::Mcp.payload_for keys" do
      data = parse(call_tool)
      keys = data["notifications"].first.keys
      expect(keys).to include("id", "title", "body_md", "url", "severity", "kind", "fires_at_iso", "read")
    end
  end

  describe "scope gate" do
    it "returns insufficient_scope error when token lacks `app`" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-app",
        scopes: [ Scopes::DEV ]
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

  describe "filters" do
    it "unread=yes returns only unread rows" do
      data = parse(call_tool(unread: "yes"))
      ids = data["notifications"].map { |r| r["id"].to_i }
      expect(ids).to contain_exactly(unread_video.id, unread_sync_error.id)
    end

    it "unread=no returns only read rows" do
      data = parse(call_tool(unread: "no"))
      ids = data["notifications"].map { |r| r["id"].to_i }
      expect(ids).to contain_exactly(read_calendar.id)
    end

    it "kind=sync_error filters to that kind" do
      data = parse(call_tool(kind: "sync_error"))
      kinds = data["notifications"].map { |r| r["kind"] }.uniq
      expect(kinds).to eq([ "sync_error" ])
    end

    it "kind=__nope__ degrades to no filter" do
      data = parse(call_tool(kind: "__nope__"))
      expect(data["notifications"].size).to eq(3)
    end

    it "severity=urgent filters to that severity" do
      data = parse(call_tool(severity: "urgent"))
      severities = data["notifications"].map { |r| r["severity"] }.uniq
      expect(severities).to eq([ "urgent" ])
    end

    it "severity=__nope__ degrades to no filter" do
      data = parse(call_tool(severity: "__nope__"))
      expect(data["notifications"].size).to eq(3)
    end
  end

  describe "pagination" do
    before do
      30.times do |i|
        travel_to(i.minutes.ago) do
          create(:notification, :video_published)
        end
      end
    end

    it "page=2 paginates" do
      data = parse(call_tool(page: 2, per_page: 25))
      expect(data["pagination"]["page"]).to eq(2)
      expect(data["notifications"].size).to be > 0
    end

    it "per_page=100 honored" do
      data = parse(call_tool(per_page: 100))
      expect(data["pagination"]["per_page"]).to eq(100)
    end

    it "per_page=1000 capped at 100" do
      data = parse(call_tool(per_page: 1000))
      expect(data["pagination"]["per_page"]).to eq(100)
    end

    it "per_page=0 floors at 1" do
      data = parse(call_tool(per_page: 0))
      expect(data["pagination"]["per_page"]).to eq(1)
    end
  end

  describe "smuggle / flaw tests" do
    it "smuggled `tenant_id` is ignored (tenant-free per Q10)" do
      result = call_tool(tenant_id: 999)
      data = parse(result)
      expect(data["notifications"].size).to eq(3)
    end

    it "deleted row does not appear" do
      unread_video.destroy!
      data = parse(call_tool)
      expect(data["notifications"].map { |r| r["id"].to_i }).not_to include(unread_video.id)
    end
  end

  describe "schema" do
    it "declares unread as enum [yes, no]" do
      schema = described_class.input_schema.to_h
      props = schema[:properties] || schema["properties"]
      unread = props[:unread] || props["unread"]
      expect((unread[:type] || unread["type"]).to_s).to eq("string")
      expect((unread[:enum] || unread["enum"]).map(&:to_s)).to contain_exactly("yes", "no")
    end

    it "rejects unknown properties" do
      schema = described_class.input_schema.to_h
      additional = schema.key?(:additionalProperties) ? schema[:additionalProperties] : schema["additionalProperties"]
      expect(additional).to eq(false)
    end
  end
end
