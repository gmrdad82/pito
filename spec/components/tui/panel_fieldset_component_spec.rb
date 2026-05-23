require "rails_helper"

RSpec.describe Tui::PanelFieldsetComponent, type: :component do
  describe "default render" do
    subject(:rendered) do
      render_inline(described_class.new) { "body content" }
    end

    it "renders a fieldset with the canonical class" do
      expect(rendered.css("fieldset.tui-panel-fieldset")).to be_present
    end

    it "yields content into the fieldset body" do
      expect(rendered.css("fieldset.tui-panel-fieldset").text).to include("body content")
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
end
