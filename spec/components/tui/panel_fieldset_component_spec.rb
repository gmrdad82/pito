require "rails_helper"

RSpec.describe Tui::PanelFieldsetComponent, type: :component do
  describe "default render" do
    subject(:rendered) do
      render_inline(described_class.new) { "body content" }
    end

    it "renders a fieldset with the canonical class" do
      expect(rendered.css("fieldset.tui-panel-fieldset")).to be_present
    end

    it "yields content into the inner scroll wrapper" do
      expect(rendered.css("fieldset.tui-panel-fieldset .tui-panel-fieldset__scroll").text).to include("body content")
    end

    it "auto-mounts the tui-scroll-indicator Stimulus controller" do
      controllers = rendered.css("fieldset").first["data-controller"].to_s.split
      expect(controllers).to include("tui-scroll-indicator")
    end

    it "renders the scroll indicator ▲ and ▼ glyphs inside the fieldset" do
      top = rendered.css("fieldset .tui-scroll-indicator--top").first
      bottom = rendered.css("fieldset .tui-scroll-indicator--bottom").first
      expect(top).to be_present
      expect(bottom).to be_present
      expect(top.text.strip).to eq("▲")
      expect(bottom.text.strip).to eq("▼")
    end

    it "wraps content in .tui-panel-fieldset__scroll with scroll Stimulus target" do
      wrapper = rendered.css("fieldset .tui-panel-fieldset__scroll").first
      expect(wrapper).to be_present
      expect(wrapper["data-tui-scroll-indicator-target"]).to eq("scroll")
    end

    it "positions scroll indicators before the inner scroll wrapper (siblings, not nested)" do
      fieldset = rendered.css("fieldset").first
      children = fieldset.children.select { |n| n.element? }
      # Indicator spans come before the scroll wrapper div
      indicator_indices = children.each_with_index.filter_map { |n, i| i if n["class"].to_s.include?("tui-scroll-indicator") }
      wrapper_index = children.each_with_index.find_index { |n, _| n["class"].to_s.include?("tui-panel-fieldset__scroll") }
      expect(indicator_indices).to all(be < wrapper_index)
    end
  end

  describe "with caller-supplied data: controller" do
    subject(:rendered) do
      render_inline(
        described_class.new(data: { controller: "sessions-bulk-revoke" })
      ) { "body" }
    end

    it "MERGES tui-scroll-indicator with the caller controller (does not overwrite)" do
      controllers = rendered.css("fieldset").first["data-controller"].to_s.split
      expect(controllers).to include("sessions-bulk-revoke")
      expect(controllers).to include("tui-scroll-indicator")
    end

    it "preserves caller order — caller controller first, scroll indicator appended" do
      raw = rendered.css("fieldset").first["data-controller"].to_s
      expect(raw).to eq("sessions-bulk-revoke tui-scroll-indicator")
    end
  end

  describe "with caller-supplied multi-controller string" do
    subject(:rendered) do
      render_inline(
        described_class.new(data: { controller: "a b" })
      ) { "" }
    end

    it "appends tui-scroll-indicator at the end of the existing list" do
      raw = rendered.css("fieldset").first["data-controller"].to_s
      expect(raw).to eq("a b tui-scroll-indicator")
    end
  end

  describe "with class_name:" do
    subject(:rendered) do
      render_inline(described_class.new(class_name: "extra-class")) { "" }
    end

    it "appends extra classes alongside tui-panel-fieldset" do
      classes = rendered.css("fieldset").first["class"].to_s.split
      expect(classes).to include("tui-panel-fieldset")
      expect(classes).to include("extra-class")
    end
  end

  describe "axis: :vertical (default)" do
    subject(:rendered) do
      render_inline(described_class.new) { "body content" }
    end

    it "emits data-tui-scroll-indicator-axis-value=vertical" do
      fieldset = rendered.css("fieldset").first
      expect(fieldset["data-tui-scroll-indicator-axis-value"]).to eq("vertical")
    end

    it "does NOT add the --horizontal modifier class" do
      classes = rendered.css("fieldset").first["class"].to_s.split
      expect(classes).not_to include("tui-panel-fieldset--horizontal")
    end

    it "renders the vertical ▲ ▼ █ scroll indicator glyphs (right-border, non-interactive)" do
      expect(rendered.css(".tui-scroll-indicator--top").text.strip).to eq("▲")
      expect(rendered.css(".tui-scroll-indicator--handle").text.strip).to eq("█")
      expect(rendered.css(".tui-scroll-indicator--bottom").text.strip).to eq("▼")
    end

    it "marks all scroll indicator spans aria-hidden (non-interactive)" do
      rendered.css(".tui-scroll-indicator").each do |span|
        expect(span["aria-hidden"]).to eq("true")
      end
    end
  end

  describe "axis: :horizontal (shelf / horizontal scroll context)" do
    subject(:rendered) do
      render_inline(described_class.new(axis: :horizontal, class_name: "my-shelf")) { "shelf content" }
    end

    it "adds the --horizontal modifier class" do
      classes = rendered.css("fieldset").first["class"].to_s.split
      expect(classes).to include("tui-panel-fieldset--horizontal")
    end

    it "emits data-tui-scroll-indicator-axis-value=horizontal" do
      fieldset = rendered.css("fieldset").first
      expect(fieldset["data-tui-scroll-indicator-axis-value"]).to eq("horizontal")
    end

    it "renders the horizontal ◀ ▶ ▬ scroll indicator glyphs (bottom-border)" do
      expect(rendered.css(".tui-scroll-indicator--left").text.strip).to eq("◀")
      expect(rendered.css(".tui-scroll-indicator--right").text.strip).to eq("▶")
      handle = rendered.css(".tui-scroll-indicator--horizontal.tui-scroll-indicator--handle")
      expect(handle.text.strip).to eq("▬")
    end

    it "does NOT render the vertical ▲ ▼ glyphs" do
      expect(rendered.css(".tui-scroll-indicator--top")).to be_empty
      expect(rendered.css(".tui-scroll-indicator--bottom")).to be_empty
    end

    it "marks all horizontal scroll indicator spans aria-hidden (non-interactive)" do
      rendered.css(".tui-scroll-indicator").each do |span|
        expect(span["aria-hidden"]).to eq("true")
      end
    end

    it "yields content into the inner scroll wrapper" do
      expect(rendered.css(".tui-panel-fieldset__scroll").text).to include("shelf content")
    end
  end
end
