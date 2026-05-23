require "rails_helper"

RSpec.describe Tui::ViewToggleComponent, type: :component do
  let(:views) do
    [
      { name: :month,    label: "month" },
      { name: :schedule, label: "schedule" }
    ]
  end

  describe "width-stable active/inactive variants" do
    subject(:rendered) do
      render_inline(described_class.new(views: views, current: :month))
    end

    it "renders the active view with surrounding spaces (no brackets)" do
      active = rendered.css(".tui-view-toggle__view--active").first
      expect(active).to be_present
      expect(active.text).to eq(" month ")
    end

    it "renders the inactive view with brackets" do
      inactive = rendered.css(".tui-view-toggle__view--inactive").first
      expect(inactive).to be_present
      expect(inactive.text).to eq("[schedule]")
    end

    it "renders active+inactive at the same character width (label.length + 2)" do
      active = rendered.css(".tui-view-toggle__view--active").first.text
      inactive = rendered.css(".tui-view-toggle__view--inactive").first.text
      expect(active.length).to eq("month".length + 2)
      expect(inactive.length).to eq("schedule".length + 2)
      # Each view's visible text is label + 2 chars regardless of variant.
      # The pair widths differ by label-length, but each label preserves
      # the +2 invariant per the locked design.
    end
  end

  describe "color modifier" do
    it "applies is-success on active by default" do
      rendered = render_inline(described_class.new(views: views, current: :schedule))
      active = rendered.css(".tui-view-toggle__view--active").first
      expect(active["class"]).to include("is-success")
    end

    it "applies the chosen active_color modifier" do
      rendered = render_inline(described_class.new(views: views, current: :month, active_color: :warn))
      active = rendered.css(".tui-view-toggle__view--active").first
      expect(active["class"]).to include("is-warn")
    end

    it "raises when active_color is not in the allowlist" do
      expect {
        described_class.new(views: views, current: :month, active_color: :totally_made_up)
      }.to raise_error(ArgumentError, /active_color must be one of/)
    end
  end

  describe "swap" do
    it "swaps which view is active when current changes" do
      r1 = render_inline(described_class.new(views: views, current: :month))
      r2 = render_inline(described_class.new(views: views, current: :schedule))

      r1_active = r1.css(".tui-view-toggle__view--active").first.text
      r2_active = r2.css(".tui-view-toggle__view--active").first.text
      expect(r1_active).to eq(" month ")
      expect(r2_active).to eq(" schedule ")

      r1_inactive = r1.css(".tui-view-toggle__view--inactive").first.text
      r2_inactive = r2.css(".tui-view-toggle__view--inactive").first.text
      expect(r1_inactive).to eq("[schedule]")
      expect(r2_inactive).to eq("[month]")
    end
  end

  describe "Stimulus wiring" do
    subject(:rendered) do
      render_inline(described_class.new(
        views: views,
        current: :month,
        event_name: "calendar:view-changed"
      ))
    end

    it "wires the tui-view-toggle Stimulus controller on the root" do
      root = rendered.css(".tui-view-toggle").first
      expect(root["data-controller"]).to eq("tui-view-toggle")
    end

    it "emits the current-value + event-name-value on the root" do
      root = rendered.css(".tui-view-toggle").first
      expect(root["data-tui-view-toggle-current-value"]).to eq("month")
      expect(root["data-tui-view-toggle-event-name-value"]).to eq("calendar:view-changed")
    end

    it "wires each button with click->tui-view-toggle#switch + view param" do
      buttons = rendered.css("button.tui-view-toggle__view")
      expect(buttons.size).to eq(2)
      buttons.each do |btn|
        expect(btn["data-action"]).to eq("click->tui-view-toggle#switch")
        expect(btn["data-tui-view-toggle-view-param"]).to be_in(%w[month schedule])
      end
    end

    it "marks each button as a tui-focusable for keyboard cursor traversal" do
      buttons = rendered.css("button.tui-view-toggle__view")
      keys = buttons.map { |b| b["data-tui-focusable-key"] }
      expect(keys).to match_array(%w[month schedule])
    end

    it "sets aria-pressed=true on the active button and false on inactive" do
      active = rendered.css(".tui-view-toggle__view--active").first
      inactive = rendered.css(".tui-view-toggle__view--inactive").first
      expect(active["aria-pressed"]).to eq("true")
      expect(inactive["aria-pressed"]).to eq("false")
    end
  end

  describe "defaults" do
    it "defaults event_name to tui:view-toggle-changed" do
      rendered = render_inline(described_class.new(views: views, current: :month))
      root = rendered.css(".tui-view-toggle").first
      expect(root["data-tui-view-toggle-event-name-value"]).to eq("tui:view-toggle-changed")
    end
  end
end
