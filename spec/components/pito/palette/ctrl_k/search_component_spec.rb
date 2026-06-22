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

  describe "terminal block caret" do
    it "wraps the search input in a caret + trail controller host" do
      wrap = node.css("[data-controller~='pito--terminal-caret'][data-controller~='pito--cursor-trail']").first
      expect(wrap).to be_present
    end

    it "marks the search input as the caret field target (keeping the palette target)" do
      input = node.css("input[data-pito--terminal-caret-target='field']").first
      expect(input).to be_present
      expect(input["data-pito--command-palette-target"]).to eq("search")
    end

    it "renders the .terminal-caret block target" do
      expect(node.css("span.terminal-caret[data-pito--terminal-caret-target='block']")).not_to be_empty
    end

    it "keeps the input monospace and hides the native caret (.font-mono + .pito-caret-input)" do
      input = node.css("input[data-pito--terminal-caret-target='field']").first
      expect(input["class"]).to include("font-mono")
      expect(input["class"]).to include("pito-caret-input")
    end
  end
end
