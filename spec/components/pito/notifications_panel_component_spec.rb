require "rails_helper"

RSpec.describe Pito::NotificationsPanelComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(
      discord_webhook: nil,
      slack_webhook: nil
    ))
  end

  let(:root) { rendered.css("section.pito-panel").first }

  it "renders the canonical pito-panel section wrapper" do
    expect(root).to be_present
    expect(root["class"]).to include("pito-panel")
    expect(root["class"]).to include("pito-panel--notifications")
  end

  it "resolves the title from the canonical home-panel i18n namespace" do
    expect(I18n.t("tui.home.panels.notifications.title")).to eq("notifications settings")
    title_span = rendered.css(".pito-pane__title").first
    expect(title_span).to be_present
    expect(title_span.text.strip).to eq("notifications settings")
  end

  it "wires the tui-panel-cable Stimulus controller" do
    expect(root["data-controller"]).to include("tui-panel-cable")
  end

  it "emits the canonical cable name + screen data values" do
    expect(root["data-tui-panel-cable-name-value"]).to eq("notifications")
    expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
  end

  it "registers the panel as a tui-cursor target" do
    expect(root["data-tui-cursor-target"]).to eq("panel")
  end

  it "emits the panel name into both cable + panel scope data values" do
    expect(root["data-tui-panel-name-value"]).to eq("notifications")
  end

  it "joins the locked focusables list (with notifications_sync leading) into the panel data value" do
    expect(root["data-tui-panel-focusables-value"]).to eq(
      "notifications_sync,all,daily,discord_webhook,discord_update,discord_help,slack_webhook,slack_update,slack_help"
    )
  end

  it "JSON-encodes an empty keybinds Hash into the panel data value" do
    expect(root["data-tui-panel-keybinds-value"]).to eq("{}")
  end

  describe "#cable_channel_for" do
    it "derives the canonical pito:home:notifications stream name" do
      component = described_class.new(discord_webhook: nil, slack_webhook: nil)
      expect(component.cable_channel_for(described_class::PANEL_NAME)).to eq("pito:home:notifications")
    end
  end

  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:notifications)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end

  it "no longer defines the legacy CABLE_CHANNEL constant (Phase 2C cleanup)" do
    expect(described_class.const_defined?(:CABLE_CHANNEL)).to be(false)
  end
end
