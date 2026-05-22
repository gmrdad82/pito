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

    # FB-test-infra (2026-05-22) — Regression: the three state-name
    # data-* attrs the child `tui-sync-indicator` controller reads on
    # connect MUST be present on the root span. If any goes missing the
    # JS layer falls back to undefined and renders an empty word.
    it "seeds the three Stimulus state values on the root span" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css("[data-tui-sync-indicator-synced-value]")
      expect(page).to have_css("[data-tui-sync-indicator-syncing-value]")
      expect(page).to have_css("[data-tui-sync-indicator-disconnected-value]")
    end

    # FB-test-infra (2026-05-22) — Regression: locks the canonical
    # three state names (`synced` / `syncing` / `disconnected`) the
    # JS sync indicator paints from the activity-pulse / disconnected
    # event paths. If anyone renames the JS contract (e.g. `idle`
    # instead of `synced`) this assertion catches the drift.
    it "publishes the canonical state names (synced/syncing/disconnected)" do
      synced = I18n.t("tui.tst.sync.synced")
      syncing = I18n.t("tui.tst.sync.syncing")
      disconnected = I18n.t("tui.tst.sync.disconnected")
      expect([ synced, syncing, disconnected ]).to all(be_a(String))
      expect([ synced, syncing, disconnected ]).to all(be_present)
    end
  end
end
