require "rails_helper"

RSpec.describe Pito::CalendarPanelComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new) }

  let(:root) { rendered.css("section.pito-panel").first }

  it "renders the canonical pito-panel section wrapper" do
    expect(root).to be_present
    expect(root["class"]).to include("pito-panel")
    expect(root["class"]).to include("pito-panel--calendar")
  end

  it "renders the rescued pito-pane chrome with the i18n title" do
    title = I18n.t("tui.home.panels.calendar.title")
    expect(title).to eq("calendar")
    expect(root["class"]).to include("pane")
    expect(root["class"]).to include("pito-pane")
    header = rendered.css(".pito-pane__title").first
    expect(header).to be_present
    expect(header.text.strip).to eq(title)
  end

  it "wires the tui-panel-cable Stimulus controller" do
    expect(root["data-controller"]).to include("tui-panel-cable")
  end

  it "emits the canonical cable name + screen data values" do
    expect(root["data-tui-panel-cable-name-value"]).to eq("calendar")
    expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
  end

  it "registers the panel as a tui-cursor target" do
    expect(root["data-tui-cursor-target"]).to eq("panel")
  end

  it "registers month + schedule as the panel focusables" do
    expect(root["data-tui-panel-focusables-value"]).to eq("month,schedule")
  end

  it "emits empty keybinds map (view toggle dispatches via Stimulus events, not flat keys)" do
    expect(root["data-tui-panel-keybinds-value"]).to eq("{}")
  end

  describe "view toggle" do
    it "renders the Tui::ViewToggleComponent in the title-actions slot" do
      actions = rendered.css(".pito-pane__title-actions").first
      expect(actions).to be_present
      toggle = actions.css(".tui-view-toggle").first
      expect(toggle).to be_present
    end

    it "defaults to current_view: :month (month active + schedule inactive)" do
      buttons = rendered.css(".tui-view-toggle button")
      month = buttons.find { |b| b["data-tui-view-toggle-view-param"] == "month" }
      schedule = buttons.find { |b| b["data-tui-view-toggle-view-param"] == "schedule" }
      expect(month["class"]).to include("tui-view-toggle__view--active")
      expect(month.text).to eq(" month ")
      expect(schedule["class"]).to include("tui-view-toggle__view--inactive")
      expect(schedule.text).to eq("[schedule]")
    end

    it "renders the active variant with the is-success color modifier (Dracula green per locked design)" do
      active = rendered.css(".tui-view-toggle__view--active").first
      expect(active["class"]).to include("is-success")
    end

    it "swaps the active variant when current_view: :schedule" do
      r2 = render_inline(described_class.new(current_view: :schedule))
      buttons = r2.css(".tui-view-toggle button")
      month = buttons.find { |b| b["data-tui-view-toggle-view-param"] == "month" }
      schedule = buttons.find { |b| b["data-tui-view-toggle-view-param"] == "schedule" }
      expect(schedule["class"]).to include("tui-view-toggle__view--active")
      expect(schedule.text).to eq(" schedule ")
      expect(month["class"]).to include("tui-view-toggle__view--inactive")
      expect(month.text).to eq("[month]")
    end

    it "emits the calendar:view-changed CustomEvent name on the toggle root" do
      toggle = rendered.css(".tui-view-toggle").first
      expect(toggle["data-tui-view-toggle-event-name-value"]).to eq("calendar:view-changed")
    end

    it "raises when current_view is not in the canonical VIEWS list" do
      expect {
        described_class.new(current_view: :nonsense)
      }.to raise_error(ArgumentError, /current_view must be one of/)
    end
  end

  describe "placeholder body" do
    it "renders the placeholder body inside the panel fieldset, reflecting the current view" do
      placeholder = rendered.css(".tui-panel-fieldset .pito-panel__placeholder").first
      expect(placeholder).to be_present
      expect(placeholder.text.strip).to eq("[ month view TBD ]")
    end

    it "reflects the schedule view in the placeholder body" do
      r2 = render_inline(described_class.new(current_view: :schedule))
      placeholder = r2.css(".tui-panel-fieldset .pito-panel__placeholder").first
      expect(placeholder.text.strip).to eq("[ schedule view TBD ]")
    end
  end

  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:calendar)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end
end
