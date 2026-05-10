require "rails_helper"
require_relative "../../../app/mcp/tools/notifications_mark_all_read"

RSpec.describe Mcp::Tools::NotificationsMarkAllRead do
  let!(:unread_a) { create(:notification, :video_published) }
  let!(:unread_b) { create(:notification, :sync_error) }
  let!(:read_a)   { create(:notification, :read, :calendar_entry_firing) }

  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  it "marks all unread rows as read (happy)" do
    data = parse(call_tool)
    expect(data["marked_read"]).to eq(2)
    expect(unread_a.reload.in_app_read_at).to be_present
    expect(unread_b.reload.in_app_read_at).to be_present
  end

  it "does NOT touch already-read rows" do
    stamp = read_a.in_app_read_at
    call_tool
    expect(read_a.reload.in_app_read_at).to be_within(1.second).of(stamp)
  end

  it "returns marked_read: 0 when there is nothing to mark" do
    Notification.unread.update_all(in_app_read_at: Time.current)
    data = parse(call_tool)
    expect(data["marked_read"]).to eq(0)
  end

  it "is non-destructive (no rows deleted)" do
    expect { call_tool }.not_to change(Notification, :count)
  end

  it "does NOT require `confirm` (per master decision #3)" do
    result = call_tool
    expect(result.to_h[:isError]).to be_falsey
  end

  it "rejects when token lacks `app` scope" do
    Current.token = ApiToken.generate!(
      user: Current.user,
      name: "spec-no-app",
      scopes: [ Scopes::DEV ]
    ).first
    result = call_tool
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  it "rejects when there is no token" do
    Current.token = nil
    result = call_tool
    expect(result.to_h[:isError]).to be(true)
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
