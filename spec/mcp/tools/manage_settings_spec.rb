require "rails_helper"
require_relative "../../../app/mcp/tools/manage_settings"

RSpec.describe Mcp::Tools::ManageSettings do
  it "shows current settings" do
    result = described_class.call
    text = result.content.first[:text]

    expect(text).to include("max_panes")
    expect(text).to include("theme")
  end

  it "updates settings" do
    result = described_class.call(updates: { "max_panes" => "5", "theme" => "dark" })
    text = result.content.first[:text]

    expect(text).to include("max_panes = 5")
    expect(text).to include("theme = dark")
    expect(AppSetting.get("max_panes")).to eq("5")
    expect(AppSetting.get("theme")).to eq("dark")
  end

  it "rejects invalid theme" do
    result = described_class.call(updates: { "theme" => "rainbow" })
    text = result.content.first[:text]

    expect(text).to include("invalid theme")
  end

  it "skips unknown keys" do
    result = described_class.call(updates: { "secret" => "value" })
    text = result.content.first[:text]

    expect(text).to include("skipped unknown key")
  end
end
