require "rails_helper"

RSpec.describe Tui::PanelBase do
  let(:dummy_class) { Class.new { include Tui::PanelBase } }
  let(:instance)    { dummy_class.new }

  describe "#cable_channel_for" do
    it "returns the canonical `pito:home:<name>` string for the default screen" do
      expect(instance.cable_channel_for(:security)).to eq("pito:home:security")
    end

    it "accepts a String name and produces the same shape" do
      expect(instance.cable_channel_for("security")).to eq("pito:home:security")
    end

    it "honors a non-default screen kwarg" do
      expect(instance.cable_channel_for(:latest_videos, screen: :videos))
        .to eq("pito:videos:latest_videos")
    end

    it "stringifies a Symbol screen kwarg" do
      expect(instance.cable_channel_for(:stack, screen: :games))
        .to eq("pito:games:stack")
    end
  end

  describe "#panel_root_data" do
    let(:attrs) { instance.panel_root_data(name: :security, focusables: %w[a b], keybinds: { "r" => "bulk_revoke" }) }
    let(:data)  { attrs[:data] }

    it "wraps the attrs Hash under the :data key for spread into content_tag" do
      expect(attrs).to have_key(:data)
      expect(attrs[:data]).to be_a(Hash)
    end

    it "names the canonical Stimulus controller" do
      expect(data[:controller]).to eq("tui-panel-cable")
    end

    it "emits the cable screen value (default 'home')" do
      expect(data[:tui_panel_cable_screen_value]).to eq("home")
    end

    it "emits the cable name value" do
      expect(data[:tui_panel_cable_name_value]).to eq("security")
    end

    it "registers the panel as a tui-cursor target" do
      expect(data[:tui_cursor_target]).to eq("panel")
    end

    it "emits the panel name twice (cable + panel scope) so downstream controllers can read it" do
      expect(data[:tui_panel_name_value]).to eq("security")
    end

    it "joins focusables with comma into the focusables value string" do
      expect(data[:tui_panel_focusables_value]).to eq("a,b")
    end

    it "stringifies Symbol focusables before joining" do
      result = instance.panel_root_data(name: :stack, focusables: %i[busy queued])
      expect(result[:data][:tui_panel_focusables_value]).to eq("busy,queued")
    end

    it "emits empty focusables string when none provided" do
      result = instance.panel_root_data(name: :stack)
      expect(result[:data][:tui_panel_focusables_value]).to eq("")
    end

    it "JSON-encodes the keybinds Hash" do
      parsed = JSON.parse(data[:tui_panel_keybinds_value])
      expect(parsed).to eq("r" => "bulk_revoke")
    end

    it "emits `{}` for empty keybinds" do
      result = instance.panel_root_data(name: :stack)
      expect(result[:data][:tui_panel_keybinds_value]).to eq("{}")
    end

    it "honors a non-default screen kwarg" do
      result = instance.panel_root_data(name: :latest_videos, screen: :videos)
      expect(result[:data][:tui_panel_cable_screen_value]).to eq("videos")
    end

    it "stringifies Symbol screen kwarg" do
      result = instance.panel_root_data(name: :stack, screen: :games)
      expect(result[:data][:tui_panel_cable_screen_value]).to eq("games")
    end

    it "stringifies a Symbol name" do
      result = instance.panel_root_data(name: :notifications_feed)
      expect(result[:data][:tui_panel_cable_name_value]).to eq("notifications_feed")
      expect(result[:data][:tui_panel_name_value]).to eq("notifications_feed")
    end
  end

  describe "#panel_root_data — panel_commands (Phase 1C)" do
    let(:cmds) do
      [
        { key: "reindex", name: "reindex", hint: "rebuild", action_name: :reindex_meilisearch },
        { key: "sync", name: "sync toggle", hint: "toggle sync", action_name: :sync_toggle, args: { target: "x" } }
      ]
    end

    it "serializes panel_commands kwarg to JSON in data-panel-commands" do
      result = instance.panel_root_data(name: :stack, panel_commands: cmds)
      raw = result[:data][:panel_commands]
      expect(raw).to be_present
      parsed = JSON.parse(raw)
      expect(parsed.length).to eq(2)
      expect(parsed.first["key"]).to eq("reindex")
      expect(parsed.last["args"]).to eq("target" => "x")
    end

    it "omits the data-panel-commands attr when no commands given (kwarg + no #panel_commands method)" do
      result = instance.panel_root_data(name: :stack)
      expect(result[:data]).not_to have_key(:panel_commands)
    end

    it "introspects the including VC's #panel_commands method when kwarg omitted" do
      cls = Class.new do
        include Tui::PanelBase
        def panel_commands
          [ { key: "x", name: "x", hint: "x", action_name: :sync_toggle } ]
        end
      end
      result = cls.new.panel_root_data(name: :stack)
      parsed = JSON.parse(result[:data][:panel_commands])
      expect(parsed.length).to eq(1)
      expect(parsed.first["key"]).to eq("x")
    end

    it "serializes an empty array as []" do
      result = instance.panel_root_data(name: :stack, panel_commands: [])
      expect(result[:data][:panel_commands]).to eq("[]")
    end
  end

  describe "DEFAULT_SCREEN" do
    it "is frozen and equal to 'home'" do
      expect(described_class::DEFAULT_SCREEN).to eq("home")
      expect(described_class::DEFAULT_SCREEN).to be_frozen
    end
  end
end
