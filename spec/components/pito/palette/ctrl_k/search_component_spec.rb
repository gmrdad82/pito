# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CtrlK::SearchComponent do
  subject(:node) { render_inline(described_class.new) }

  describe "search input" do
    it "renders an <input> with the correct Stimulus target" do
      input = node.css("input[data-pito--command-palette-target='search']")
      expect(input).not_to be_empty
    end

    it "has data-action wired to filter" do
      input = node.css("input[data-pito--command-palette-target='search']").first
      expect(input["data-action"]).to include("input->pito--command-palette#filter")
    end

    it "does not wire onSearchKey (navigation handled by global keydown listener)" do
      input = node.css("input[data-pito--command-palette-target='search']").first
      expect(input["data-action"]).not_to include("onSearchKey")
    end

    it "renders the placeholder from i18n" do
      input = node.css("input[data-pito--command-palette-target='search']").first
      expect(input["placeholder"]).to eq(I18n.t("pito.palette.ctrl_k.search_placeholder"))
    end
  end

  describe "title row" do
    it "renders the palette title from i18n" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.title"))
    end

    it "renders the esc hint from i18n" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.esc_hint"))
    end
  end

  describe "caret" do
    it "uses the normal native caret (no block-caret) on the search input" do
      input = node.css("input[data-pito--command-palette-target='search']").first
      expect(input).to be_present
      expect(input["class"]).to include("font-mono")
      expect(input["class"]).not_to include("pito-block-caret")
    end

    it "renders no bespoke caret/trail machinery" do
      expect(node.css("[data-controller~='pito--terminal-caret']")).to be_empty
      expect(node.css("[data-controller~='pito--cursor-trail']")).to be_empty
      expect(node.css("span.terminal-caret")).to be_empty
      expect(node.css("[data-pito--terminal-caret-target]")).to be_empty
      expect(node.css(".pito-caret-input")).to be_empty
    end
  end
end
