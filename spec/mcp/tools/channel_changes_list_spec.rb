require "rails_helper"
require_relative "../../../app/mcp/tools/channel_changes_list"

# Phase 7.5 §11g — MCP tool: `channel_changes_list`.
RSpec.describe Mcp::Tools::ChannelChangesList do
  let(:user) { Current.user }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv")
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path" do
    let!(:older) do
      create(:channel_change_log,
             channel: channel,
             changed_by_user: user,
             field: "title",
             old_value: "Old",
             new_value: "Middle",
             changed_at: 3.days.ago)
    end
    let!(:newer) do
      create(:channel_change_log,
             channel: channel,
             changed_by_user: user,
             field: "handle",
             old_value: "@old",
             new_value: "@new",
             changed_at: 1.hour.ago)
    end

    it "returns the envelope shape" do
      data = parse(described_class.call(channel: channel.to_param))
      expect(data.keys).to contain_exactly("changes", "pagination")
      expect(data["pagination"]).to include(
        "page" => 1,
        "per_page" => 50,
        "total" => 2,
        "total_pages" => 1
      )
    end

    it "rows include the locked key set" do
      data = parse(described_class.call(channel: channel.to_param))
      expect(data["changes"].first.keys).to contain_exactly(
        "id", "field", "old_value", "new_value", "changed_at", "changed_by"
      )
    end

    it "orders newest first" do
      data = parse(described_class.call(channel: channel.to_param))
      expect(data["changes"].map { |r| r["new_value"] }).to eq([ "@new", "Middle" ])
    end

    it "encodes changed_at as ISO-8601 UTC" do
      data = parse(described_class.call(channel: channel.to_param))
      expect(data["changes"].first["changed_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it "encodes changed_by as { id, username } when the FK resolves" do
      data = parse(described_class.call(channel: channel.to_param))
      row = data["changes"].first
      expect(row["changed_by"]).to eq("id" => user.id, "username" => user.username)
    end

    it "encodes changed_by as { id, username } when the FK resolves (steady state — DB FK is NOT NULL)" do
      data = parse(described_class.call(channel: channel.to_param))
      row = data["changes"].first
      expect(row["changed_by"]).to eq("id" => user.id, "username" => user.username)
    end

    it "accepts an integer id as a string" do
      data = parse(described_class.call(channel: channel.id.to_s))
      expect(data["changes"].size).to eq(2)
    end
  end

  describe "pagination" do
    before do
      55.times do |i|
        create(:channel_change_log,
               channel: channel,
               changed_by_user: user,
               field: "title",
               old_value: "t#{i}",
               new_value: "t#{i + 1}",
               changed_at: i.hours.ago)
      end
    end

    it "page=1 returns 50 rows" do
      data = parse(described_class.call(channel: channel.to_param, page: 1))
      expect(data["changes"].size).to eq(50)
      expect(data["pagination"]).to include("page" => 1, "total" => 55, "total_pages" => 2)
    end

    it "page=2 returns 5 rows" do
      data = parse(described_class.call(channel: channel.to_param, page: 2))
      expect(data["changes"].size).to eq(5)
      expect(data["pagination"]["page"]).to eq(2)
    end

    it "negative page floors at 1" do
      data = parse(described_class.call(channel: channel.to_param, page: -10))
      expect(data["pagination"]["page"]).to eq(1)
    end

    it "out-of-range page returns empty changes (no 404)" do
      result = described_class.call(channel: channel.to_param, page: 999)
      data = parse(result)
      expect(data["changes"]).to eq([])
      expect(data["pagination"]["page"]).to eq(999)
    end
  end

  describe "empty state" do
    it "returns an empty array with total: 0" do
      data = parse(described_class.call(channel: channel.to_param))
      expect(data["changes"]).to eq([])
      expect(data["pagination"]).to include("total" => 0, "total_pages" => 1)
    end
  end

  describe "scope gate" do
    it "returns insufficient_scope when the token lacks `app`" do
      record, _ = ApiToken.generate!(
        user: User.first || create(:user),
        name: "dev-only",
        scopes: [ Scopes::DEV ]
      )
      Current.token = record
      result = described_class.call(channel: channel.to_param)
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end

    it "rejects when no token at all" do
      Current.token = nil
      result = described_class.call(channel: channel.to_param)
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "validation errors" do
    it "errors when channel is missing" do
      result = described_class.call
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("channel is required")
    end

    it "errors when channel is blank" do
      result = described_class.call(channel: "")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("channel is required")
    end

    it "errors when the channel is not found" do
      result = described_class.call(channel: "no-such-channel")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("channel not found")
    end
  end

  describe "schema" do
    it "declares channel as required" do
      schema = described_class.input_schema.to_h
      required = schema[:required] || schema["required"]
      expect(required.map(&:to_s)).to include("channel")
    end

    it "declares page as integer with minimum 1" do
      schema = described_class.input_schema.to_h
      props = schema[:properties] || schema["properties"]
      page = props[:page] || props["page"]
      expect((page[:type] || page["type"]).to_s).to eq("integer")
      expect(page[:minimum] || page["minimum"]).to eq(1)
    end
  end

  describe "registration" do
    it "is named `channel_changes_list`" do
      expect(described_class.name_value).to eq("channel_changes_list")
    end

    it "is read-only annotated" do
      annotations = described_class.annotations_value
      expect(annotations.read_only_hint).to be(true)
    end
  end
end
