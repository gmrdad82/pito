require "rails_helper"

RSpec.describe Pito::SecurityPanelComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(
      sessions: sessions,
      sessions_sort: "last_seen",
      sessions_dir: "desc"
    ))
  end

  let(:sessions) { [] }
  let(:root) { rendered.css("section.pito-panel").first }

  before { allow(Current).to receive(:session).and_return(nil) }

  it "renders the canonical pito-panel section wrapper" do
    expect(root).to be_present
    expect(root["class"]).to include("pito-panel")
    expect(root["class"]).to include("pito-panel--security")
  end

  it "resolves the title from the canonical home-panel i18n namespace" do
    expect(I18n.t("tui.home.panels.security.title")).to eq("security")
    title_span = rendered.css(".pito-pane__title").first
    expect(title_span).to be_present
    expect(title_span.text.strip).to eq("security")
  end

  it "wires the tui-panel-cable Stimulus controller" do
    expect(root["data-controller"]).to include("tui-panel-cable")
  end

  it "emits the canonical cable name + screen data values" do
    expect(root["data-tui-panel-cable-name-value"]).to eq("security")
    expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
  end

  it "registers the panel as a tui-cursor target" do
    expect(root["data-tui-cursor-target"]).to eq("panel")
  end

  it "emits the panel name into both cable + panel scope data values" do
    expect(root["data-tui-panel-name-value"]).to eq("security")
  end

  it "joins the default focusables (security_sync + select_all) when sessions is empty" do
    expect(root["data-tui-panel-focusables-value"]).to eq("security_sync,select_all")
  end

  it "JSON-encodes the keybinds Hash into the panel data value" do
    parsed = JSON.parse(root["data-tui-panel-keybinds-value"])
    expect(parsed.keys).to contain_exactly("space_insert", "r")
  end

  describe "#cable_channel_for" do
    it "derives the canonical pito:home:security stream name" do
      component = described_class.new(sessions: sessions, sessions_sort: "last_seen", sessions_dir: "desc")
      expect(component.cable_channel_for(described_class::PANEL_NAME)).to eq("pito:home:security")
    end
  end

  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:security)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end

  it "no longer defines the legacy CABLE_CHANNEL constant (Phase 2C cleanup)" do
    expect(described_class.const_defined?(:CABLE_CHANNEL)).to be(false)
  end
end
