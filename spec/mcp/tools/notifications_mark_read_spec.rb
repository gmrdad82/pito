require "rails_helper"
require_relative "../../../app/mcp/tools/notifications_mark_read"

RSpec.describe Mcp::Tools::NotificationsMarkRead do
  let!(:unread_a) { create(:notification, :video_published) }
  let!(:unread_b) { create(:notification, :sync_error) }
  let!(:read_a)   { create(:notification, :read, :calendar_entry_firing) }

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  describe "happy path" do
    it "marks the supplied unread rows as read" do
      data = parse(call_tool(ids: [ unread_a.id, unread_b.id ]))
      expect(data["marked_read"]).to eq(2)
      expect(data["ids"]).to contain_exactly(unread_a.id, unread_b.id)
      expect(data["not_found_ids"]).to eq([])

      expect(unread_a.reload.in_app_read_at).to be_present
      expect(unread_b.reload.in_app_read_at).to be_present
    end

    it "is non-destructive: no Notification rows are deleted" do
      expect {
        call_tool(ids: [ unread_a.id, unread_b.id ])
      }.not_to change(Notification, :count)
    end

    it "does NOT require `confirm` (per master decision #3 — non-destructive)" do
      result = call_tool(ids: [ unread_a.id ])
      expect(result.to_h[:isError]).to be_falsey
    end

    it "skips already-read rows in the count but reports them in `ids`" do
      data = parse(call_tool(ids: [ unread_a.id, read_a.id ]))
      # Only the previously-unread row is counted — already-read row stays read.
      expect(data["marked_read"]).to eq(1)
      expect(data["ids"]).to contain_exactly(unread_a.id, read_a.id)
    end
  end

  describe "edge cases" do
    it "ids: [] returns marked_read: 0" do
      data = parse(call_tool(ids: []))
      expect(data["marked_read"]).to eq(0)
      expect(data["ids"]).to eq([])
      expect(data["not_found_ids"]).to eq([])
    end

    it "unknown id returns marked_read: 0 and reports it in not_found_ids" do
      data = parse(call_tool(ids: [ 999_999 ]))
      expect(data["marked_read"]).to eq(0)
      expect(data["not_found_ids"]).to eq([ 999_999 ])
    end

    it "mix of known + unknown updates only the known" do
      data = parse(call_tool(ids: [ unread_a.id, 999_999 ]))
      expect(data["marked_read"]).to eq(1)
      expect(data["ids"]).to eq([ unread_a.id ])
      expect(data["not_found_ids"]).to eq([ 999_999 ])
    end

    it "deduplicates repeated ids" do
      data = parse(call_tool(ids: [ unread_a.id, unread_a.id ]))
      expect(data["marked_read"]).to eq(1)
      expect(data["ids"]).to eq([ unread_a.id ])
    end

    it "is graceful on a deleted row (replay)" do
      unread_a.destroy!
      data = parse(call_tool(ids: [ unread_a.id ]))
      expect(data["marked_read"]).to eq(0)
      expect(data["not_found_ids"]).to eq([ unread_a.id ])
    end
  end

  describe "input validation" do
    it "rejects non-array ids" do
      result = call_tool(ids: "1,2,3")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("ids must be an array")
    end

    it "rejects malformed UUID-style strings (flaw test)" do
      result = call_tool(ids: [ "not-an-int" ])
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("must be integers")
    end

    it "rejects float ids" do
      result = call_tool(ids: [ 1.5 ])
      expect(result.to_h[:isError]).to be(true)
    end

    it "accepts numeric string ids" do
      data = parse(call_tool(ids: [ unread_a.id.to_s ]))
      expect(data["marked_read"]).to eq(1)
    end
  end

  describe "scope gate" do
    it "rejects when token lacks `app` scope" do
      Current.token = ApiToken.generate!(
        user: Current.user,
        name: "spec-no-app",
        scopes: [ Scopes::DEV ]
      ).first
      result = call_tool(ids: [ unread_a.id ])
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end

    it "rejects when there is no token" do
      Current.token = nil
      result = call_tool(ids: [ unread_a.id ])
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "schema" do
    it "does NOT declare a confirm property (master decision #3)" do
      schema = described_class.input_schema.to_h
      props = schema[:properties] || schema["properties"]
      expect(props.keys.map(&:to_s)).not_to include("confirm")
    end

    it "rejects unknown properties" do
      schema = described_class.input_schema.to_h
      additional = schema.key?(:additionalProperties) ? schema[:additionalProperties] : schema["additionalProperties"]
      expect(additional).to eq(false)
    end
  end
end
