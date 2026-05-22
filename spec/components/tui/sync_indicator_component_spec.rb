# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::SyncIndicatorComponent, type: :component do
  describe "synced state (:idle)" do
    subject(:component) { described_class.new(state: :idle) }

    it "renders without raising" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "renders the filled dot glyph" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-dot", text: "●")
    end

    it "renders the synced label from i18n" do
      label = I18n.t("tui.tst.sync.synced")
      render_inline(component)
      expect(page).to have_css(".sb-sync-word", text: label)
    end

    it "applies the green dot class" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-dot--green")
    end

    it "applies the idle word class" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-word--idle")
    end
  end

  describe "syncing state (:syncing)" do
    subject(:component) { described_class.new(state: :syncing) }

    it "renders the filled dot glyph" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-dot", text: "●")
    end

    it "renders the syncing label from i18n" do
      label = I18n.t("tui.tst.sync.syncing")
      render_inline(component)
      expect(page).to have_css(".sb-sync-word", text: label)
    end

    it "applies the amber dot class" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-dot--amber")
    end

    it "applies the syncing word class" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-word--syncing")
    end
  end

  describe "disconnected state (:disconnected)" do
    subject(:component) { described_class.new(state: :disconnected) }

    it "renders the X glyph (not the dot)" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-dot", text: "✗")
    end

    it "renders the disconnected label from i18n" do
      label = I18n.t("tui.tst.sync.disconnected")
      render_inline(component)
      expect(page).to have_css(".sb-sync-word", text: label)
    end

    it "applies the red dot class" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-dot--red")
    end

    it "applies the disconnected word class" do
      render_inline(component)
      expect(page).to have_css(".sb-sync-word--disconnected")
    end
  end

  describe "invalid state defaults to :idle" do
    it "falls back to idle" do
      component = described_class.new(state: :bogus)
      expect(component.state).to eq(:idle)
    end
  end

  describe "i18n data-* attrs for Stimulus" do
    it "exposes all three word values as helpers without hardcoding English" do
      component = described_class.new
      expect(component.word_synced).to eq(I18n.t("tui.tst.sync.synced"))
      expect(component.word_syncing).to eq(I18n.t("tui.tst.sync.syncing"))
      expect(component.word_disconnected).to eq(I18n.t("tui.tst.sync.disconnected"))
    end
  end
end
