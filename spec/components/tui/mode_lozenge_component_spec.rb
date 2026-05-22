require "rails_helper"

RSpec.describe Tui::ModeLozengeComponent, type: :component do
  describe "rendering per mode" do
    %i[normal insert command search].each do |m|
      it "renders the i18n word for #{m}" do
        render_inline(described_class.new(mode: m))
        expect(page).to have_css("span.bsb-mode")
        expect(page.text).to include(I18n.t("tui.mode.#{m}"))
      end
    end
  end

  describe "fallback behavior" do
    it "defaults to :normal when no kwarg given" do
      render_inline(described_class.new)
      expect(page).to have_css("span.bsb-mode")
      expect(page.text).to include(I18n.t("tui.mode.normal"))
    end

    it "falls back to :normal for unrecognised mode" do
      render_inline(described_class.new(mode: :bogus))
      expect(page.text).to include(I18n.t("tui.mode.normal"))
    end

    it "does not produce translation missing strings" do
      %i[normal insert command search].each do |m|
        render_inline(described_class.new(mode: m))
        expect(page.text).not_to include("translation missing")
      end
    end
  end

  describe "Tui::Transitionable wiring" do
    it "carries both tui-mode-lozenge and tui-transition controllers" do
      render_inline(described_class.new(mode: :normal))
      host = page.find("span.bsb-mode")
      controller_attr = host["data-controller"].to_s.split
      expect(controller_attr).to include("tui-mode-lozenge")
      expect(controller_attr).to include("tui-transition")
    end

    it "declares the colocated tui-transition outlet" do
      render_inline(described_class.new(mode: :normal))
      host = page.find("span.bsb-mode")
      expect(host["data-tui-mode-lozenge-tui-transition-outlet"]).to eq(".bsb-mode")
    end

    it "emits the tui-transition effect + value data attrs" do
      render_inline(described_class.new(mode: :insert))
      host = page.find("span.bsb-mode")
      expect(host["data-tui-transition-effect-value"]).to eq("scramble-settle")
      expect(host["data-tui-transition-value-value"]).to eq(I18n.t("tui.mode.insert"))
    end

    {
      normal:  "muted",
      insert:  "accent",
      command: "accent",
      search:  "success"
    }.each do |m, color|
      it "maps mode :#{m} to color #{color} on data-tui-transition-color-value" do
        render_inline(described_class.new(mode: m))
        expect(page.find("span.bsb-mode")["data-tui-transition-color-value"]).to eq(color)
      end
    end

    it "emits all four per-mode word data-attrs so the delegator can swap without a server hop" do
      render_inline(described_class.new(mode: :normal))
      host = page.find("span.bsb-mode")
      expect(host["data-tui-mode-lozenge-normal-value"]).to  eq(I18n.t("tui.mode.normal"))
      expect(host["data-tui-mode-lozenge-insert-value"]).to  eq(I18n.t("tui.mode.insert"))
      expect(host["data-tui-mode-lozenge-command-value"]).to eq(I18n.t("tui.mode.command"))
      expect(host["data-tui-mode-lozenge-search-value"]).to  eq(I18n.t("tui.mode.search"))
    end

    it "no longer emits the legacy bsb-mode--<mode> BEM modifier" do
      render_inline(described_class.new(mode: :command))
      classes = page.find("span.bsb-mode")[:class].to_s.split
      expect(classes).not_to include("bsb-mode--command")
      expect(classes).not_to include("bsb-mode--normal")
      expect(classes).not_to include("bsb-mode--insert")
      expect(classes).not_to include("bsb-mode--search")
    end

    it "no longer carries the legacy tui-bottom-status-bar target attribute" do
      render_inline(described_class.new(mode: :normal))
      expect(page).to have_no_css("[data-tui-bottom-status-bar-target='mode']")
    end
  end
end
