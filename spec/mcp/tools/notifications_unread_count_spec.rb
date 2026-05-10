require "rails_helper"
require_relative "../../../app/mcp/tools/notifications_unread_count"

RSpec.describe Mcp::Tools::NotificationsUnreadCount do
  def call_tool(**args)
    described_class.call(**args)
  end

  def parse(result)
    JSON.parse(result.content.first[:text])
  end

  it "returns {count: 0} when no unread rows exist" do
    data = parse(call_tool)
    expect(data).to eq({ "count" => 0 })
  end

  it "returns the unread count" do
    create_list(:notification, 3, :video_published)
    create(:notification, :read, :video_published)
    data = parse(call_tool)
    expect(data["count"]).to eq(3)
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

  it "ignores extra params (additionalProperties: false)" do
    create(:notification, :video_published)
    data = parse(call_tool)
    expect(data["count"]).to eq(1)
  end
end
