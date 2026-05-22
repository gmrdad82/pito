# frozen_string_literal: true

require "rails_helper"

# Tui::SyncIndicatorComponent — word-only, transitionable.
#
# Phase 2A (2026-05-22) — glyphs (●/◐/✗) dropped. The VC opts into the
# canonical Tui::Transitionable mixin and is consumed by a thin
# `tui-sync-indicator` Stimulus controller that delegates to a colocated
# `tui-transition` outlet. These specs lock the rendered data-attr
# contract the JS layer reads.
RSpec.describe Tui::SyncIndicatorComponent, type: :component do
  describe "rendered word (i18n)" do
    it "renders the synced word for :synced" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css(".tui-sync-word", text: I18n.t("tui.tst.sync.synced"))
    end

    it "renders the syncing word for :syncing" do
      render_inline(described_class.new(state: :syncing))
      expect(page).to have_css(".tui-sync-word", text: I18n.t("tui.tst.sync.syncing"))
    end

    it "renders the disconnected word for :disconnected" do
      render_inline(described_class.new(state: :disconnected))
      expect(page).to have_css(".tui-sync-word", text: I18n.t("tui.tst.sync.disconnected"))
    end

    it "accepts :idle as a soft alias for :synced (broadcaster wire compat)" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(".tui-sync-word", text: I18n.t("tui.tst.sync.synced"))
    end

    it "falls back to :synced for invalid input" do
      component = described_class.new(state: :bogus)
      expect(component.state).to eq(:synced)
    end
  end

  describe "glyph removal" do
    it "renders no dot glyph (●)" do
      render_inline(described_class.new(state: :synced))
      expect(page.native.to_html).not_to include("●")
    end

    it "renders no half-dot glyph (◐)" do
      render_inline(described_class.new(state: :syncing))
      expect(page.native.to_html).not_to include("◐")
    end

    it "renders no X glyph (✗) on disconnected state" do
      render_inline(described_class.new(state: :disconnected))
      expect(page.native.to_html).not_to include("✗")
    end

    it "does not emit the legacy sb-sync-dot class" do
      render_inline(described_class.new(state: :synced))
      expect(page).not_to have_css(".sb-sync-dot")
    end
  end

  describe "tui-transition data-attrs (Transitionable contract)" do
    it "wires both controllers in data-controller (tui-sync-indicator + tui-transition)" do
      render_inline(described_class.new(state: :synced))
      controller_attr = page.find(".tui-sync-word")["data-controller"]
      expect(controller_attr).to include("tui-sync-indicator")
      expect(controller_attr).to include("tui-transition")
    end

    it "emits align=right" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-align-value="right"]')
    end

    it "emits scramble-settle as the effect" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-effect-value="scramble-settle"]')
    end

    it "emits the initial value matching the i18n word for synced" do
      render_inline(described_class.new(state: :synced))
      synced = I18n.t("tui.tst.sync.synced")
      expect(page).to have_css(%(.tui-sync-word[data-tui-transition-value-value="#{synced}"]))
    end
  end

  describe "color contract" do
    it "is accent for :synced" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="accent"]')
    end

    it "is accent for :syncing" do
      render_inline(described_class.new(state: :syncing))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="accent"]')
    end

    it "is pink for :disconnected" do
      render_inline(described_class.new(state: :disconnected))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="pink"]')
    end
  end

  describe "shimmer contract (syncing only)" do
    it "is yes for :syncing" do
      render_inline(described_class.new(state: :syncing))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="yes"]')
    end

    it "is no for :synced" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
    end

    it "is no for :disconnected" do
      render_inline(described_class.new(state: :disconnected))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
    end
  end

  describe "per-state word data-* attrs (JS contract)" do
    it "seeds the three Stimulus state values on the root span" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css("[data-tui-sync-indicator-synced-value]")
      expect(page).to have_css("[data-tui-sync-indicator-syncing-value]")
      expect(page).to have_css("[data-tui-sync-indicator-disconnected-value]")
    end

    it "exposes the i18n words via the data-attrs" do
      render_inline(described_class.new(state: :synced))
      synced = I18n.t("tui.tst.sync.synced")
      syncing = I18n.t("tui.tst.sync.syncing")
      disconnected = I18n.t("tui.tst.sync.disconnected")
      expect(page).to have_css(%([data-tui-sync-indicator-synced-value="#{synced}"]))
      expect(page).to have_css(%([data-tui-sync-indicator-syncing-value="#{syncing}"]))
      expect(page).to have_css(%([data-tui-sync-indicator-disconnected-value="#{disconnected}"]))
    end
  end

  describe "outlet wiring (tui-transition)" do
    it "wires the tui-transition outlet selector pointing at .tui-sync-word" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css(
        '.tui-sync-word[data-tui-sync-indicator-tui-transition-outlet=".tui-sync-word"]'
      )
    end
  end

  describe "top-status-bar target hook" do
    it "preserves the legacy `sync` status-bar target on the root span" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css('.tui-sync-word[data-tui-status-bar-target="sync"]')
    end
  end

  describe "i18n helpers" do
    it "exposes all three word values without hardcoding English" do
      component = described_class.new
      expect(component.word_synced).to eq(I18n.t("tui.tst.sync.synced"))
      expect(component.word_syncing).to eq(I18n.t("tui.tst.sync.syncing"))
      expect(component.word_disconnected).to eq(I18n.t("tui.tst.sync.disconnected"))
    end
  end

  describe "width lock (CSS class is the carrier)" do
    # The `.tui-sync-word { min-width: 13ch }` rule lives in
    # app/assets/tailwind/application.css and is the single source of
    # truth for the cell width. The VC only needs to emit the class so
    # the rule applies — assert that here.
    it "carries the .tui-sync-word class so the 13ch min-width applies" do
      render_inline(described_class.new(state: :synced))
      expect(page).to have_css(".tui-sync-word")
    end
  end
end
