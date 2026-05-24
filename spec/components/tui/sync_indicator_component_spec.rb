# frozen_string_literal: true

require "rails_helper"

# Tui::SyncIndicatorComponent — checkbox-style, transitionable.
#
# Phase 1C (2026-05-24) — three states: idle [ ] / active [x] / paused [-].
# "disconnected" state dropped; cable drops are treated as idle.
# The full display string (glyph + word) is emitted as the transition value
# and also seeded as per-state data-* attrs for the JS layer.
RSpec.describe Tui::SyncIndicatorComponent, type: :component do
  let(:idle_display)   { "[ ] #{I18n.t("tui.tst.sync.idle")}" }
  let(:active_display) { "[x] #{I18n.t("tui.tst.sync.active")}" }
  let(:paused_display) { "[-] #{I18n.t("tui.tst.sync.paused")}" }

  describe "default state" do
    it "defaults to :idle" do
      component = described_class.new
      expect(component.state).to eq(:idle)
    end

    it "falls back to :idle for unknown input" do
      component = described_class.new(state: :bogus)
      expect(component.state).to eq(:idle)
    end
  end

  describe "display_value (checkbox glyph + word)" do
    it "renders '[ ] sync' for :idle" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(".tui-sync-word", text: idle_display)
    end

    it "renders '[x] sync' for :active" do
      render_inline(described_class.new(state: :active))
      expect(page).to have_css(".tui-sync-word", text: active_display)
    end

    it "renders '[-] sync' for :paused" do
      render_inline(described_class.new(state: :paused))
      expect(page).to have_css(".tui-sync-word", text: paused_display)
    end
  end

  describe "no legacy state names" do
    it "treats :synced as invalid and falls back to :idle" do
      component = described_class.new(state: :synced)
      expect(component.state).to eq(:idle)
    end

    it "treats :syncing as invalid and falls back to :idle" do
      component = described_class.new(state: :syncing)
      expect(component.state).to eq(:idle)
    end

    it "treats :disconnected as invalid and falls back to :idle" do
      component = described_class.new(state: :disconnected)
      expect(component.state).to eq(:idle)
    end
  end

  describe "tui-transition data-attrs (Transitionable contract)" do
    it "wires both controllers: tui-sync-indicator + tui-transition" do
      render_inline(described_class.new(state: :idle))
      controller_attr = page.find(".tui-sync-word")["data-controller"]
      expect(controller_attr).to include("tui-sync-indicator")
      expect(controller_attr).to include("tui-transition")
    end

    it "emits align=right" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-align-value="right"]')
    end

    it "emits scramble-settle as the effect" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-effect-value="scramble-settle"]')
    end

    it "emits the full display value (glyph + word) as the transition value for :idle" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(%(.tui-sync-word[data-tui-transition-value-value="#{idle_display}"]))
    end

    it "emits the full display value for :active" do
      render_inline(described_class.new(state: :active))
      expect(page).to have_css(%(.tui-sync-word[data-tui-transition-value-value="#{active_display}"]))
    end

    it "emits the full display value for :paused" do
      render_inline(described_class.new(state: :paused))
      expect(page).to have_css(%(.tui-sync-word[data-tui-transition-value-value="#{paused_display}"]))
    end
  end

  describe "color contract" do
    it "is muted for :idle" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="muted"]')
    end

    it "is accent for :active" do
      render_inline(described_class.new(state: :active))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="accent"]')
    end

    it "is accent-pale for :paused" do
      render_inline(described_class.new(state: :paused))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="accent-pale"]')
    end
  end

  describe "shimmer contract (active only)" do
    it "is yes for :active" do
      render_inline(described_class.new(state: :active))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="yes"]')
    end

    it "is no for :idle" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
    end

    it "is no for :paused" do
      render_inline(described_class.new(state: :paused))
      expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
    end
  end

  describe "per-state display value data-* attrs (JS contract)" do
    it "seeds idle, active, and paused Stimulus values on the root span" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css("[data-tui-sync-indicator-idle-value]")
      expect(page).to have_css("[data-tui-sync-indicator-active-value]")
      expect(page).to have_css("[data-tui-sync-indicator-paused-value]")
    end

    it "exposes the full display strings via data-attrs" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(%([data-tui-sync-indicator-idle-value="#{idle_display}"]))
      expect(page).to have_css(%([data-tui-sync-indicator-active-value="#{active_display}"]))
      expect(page).to have_css(%([data-tui-sync-indicator-paused-value="#{paused_display}"]))
    end

    it "does NOT emit legacy disconnected value attr" do
      render_inline(described_class.new(state: :idle))
      expect(page.native.to_html).not_to include("data-tui-sync-indicator-disconnected-value")
    end

    it "does NOT emit legacy synced value attr" do
      render_inline(described_class.new(state: :idle))
      expect(page.native.to_html).not_to include("data-tui-sync-indicator-synced-value")
    end

    it "does NOT emit legacy syncing value attr" do
      render_inline(described_class.new(state: :idle))
      expect(page.native.to_html).not_to include("data-tui-sync-indicator-syncing-value")
    end
  end

  describe "outlet wiring (tui-transition)" do
    it "wires the tui-transition outlet selector pointing at .tui-sync-word" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(
        '.tui-sync-word[data-tui-sync-indicator-tui-transition-outlet=".tui-sync-word"]'
      )
    end
  end

  describe "top-status-bar target hook" do
    it "emits the `sync` status-bar target on the root span" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css('.tui-sync-word[data-tui-status-bar-target="sync"]')
    end
  end

  describe "word helpers" do
    it "word_idle returns the full idle display string" do
      component = described_class.new
      expect(component.word_idle).to eq(idle_display)
    end

    it "word_active returns the full active display string" do
      component = described_class.new
      expect(component.word_active).to eq(active_display)
    end

    it "word_paused returns the full paused display string" do
      component = described_class.new
      expect(component.word_paused).to eq(paused_display)
    end
  end

  describe "CSS class hook" do
    it "carries the .tui-sync-word class" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(".tui-sync-word")
    end
  end
end
