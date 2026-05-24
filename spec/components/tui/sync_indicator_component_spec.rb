# frozen_string_literal: true

require "rails_helper"

# Tui::SyncIndicatorComponent — checkbox-style, transitionable, two-mode VC.
#
# Phase 1D (2026-05-24) — four states (idle / active / syncing / disconnected)
# x two modes (:tst / :target). Replaces the deleted PauseControlComponent;
# unifies TST aggregate + per-panel/per-sub-panel control under one VC.
RSpec.describe Tui::SyncIndicatorComponent, type: :component do
  let(:idle_word)         { I18n.t("tui.tst.sync.idle") }
  let(:active_word)       { I18n.t("tui.tst.sync.active") }
  let(:disconnected_word) { I18n.t("tui.tst.sync.disconnected", default: idle_word) }
  let(:idle_display)         { "[ ] #{idle_word}" }
  let(:active_display)       { "[x] #{active_word}" }
  let(:syncing_display)      { "[x] #{active_word}" }
  let(:disconnected_display) { "[!] #{disconnected_word}" }

  describe "default state + mode" do
    it "defaults to :idle state" do
      expect(described_class.new.state).to eq(:idle)
    end

    it "defaults to :tst mode" do
      expect(described_class.new.mode).to eq(:tst)
    end

    it "falls back to :idle for unknown state" do
      expect(described_class.new(state: :bogus).state).to eq(:idle)
    end

    it "falls back to :tst for unknown mode" do
      expect(described_class.new(mode: :bogus).mode).to eq(:tst)
    end

    it "raises when :target mode is missing a target:" do
      expect { described_class.new(mode: :target) }.to raise_error(ArgumentError)
    end
  end

  # ─── :tst mode — aggregate (default) ──────────────────────────────
  describe ":tst mode (aggregate read-only)" do
    describe "checkbox glyph + word for each state" do
      it "renders '[ ] sync' for :idle" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css(".tui-sync-word", text: idle_display)
      end

      it "renders '[x] sync' for :active" do
        render_inline(described_class.new(state: :active))
        expect(page).to have_css(".tui-sync-word", text: active_display)
      end

      it "renders '[x] sync' for :syncing (same glyph + word as :active)" do
        render_inline(described_class.new(state: :syncing))
        expect(page).to have_css(".tui-sync-word", text: syncing_display)
      end

      it "renders '[!] sync' for :disconnected" do
        render_inline(described_class.new(state: :disconnected))
        expect(page).to have_css(".tui-sync-word", text: disconnected_display)
      end
    end

    describe "tag shape" do
      it "renders a <span>, not a <button>, in :tst mode" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css("span.tui-sync-word")
        expect(page).to have_no_css("button.tui-sync-word")
      end

      it "emits the top-status-bar target attr" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css('.tui-sync-word[data-tui-status-bar-target="sync"]')
      end

      it "does NOT emit a click action in :tst mode" do
        render_inline(described_class.new(state: :idle))
        html = page.native.to_html
        expect(html).not_to include("click->tui-sync-indicator#toggle")
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

      it "is accent for :syncing" do
        render_inline(described_class.new(state: :syncing))
        expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="accent"]')
      end

      it "is pink (red) for :disconnected" do
        render_inline(described_class.new(state: :disconnected))
        expect(page).to have_css('.tui-sync-word[data-tui-transition-color-value="pink"]')
      end
    end

    describe "shimmer contract" do
      it "is no for :idle" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
      end

      it "is no for :active (work present but not currently receiving)" do
        render_inline(described_class.new(state: :active))
        expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
      end

      it "is yes for :syncing (currently receiving cable content)" do
        render_inline(described_class.new(state: :syncing))
        expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="yes"]')
      end

      it "is no for :disconnected" do
        render_inline(described_class.new(state: :disconnected))
        expect(page).to have_css('.tui-sync-word[data-tui-transition-shimmer-value="no"]')
      end
    end

    describe "tui-transition data-attrs" do
      it "wires both controllers: tui-sync-indicator + tui-transition" do
        render_inline(described_class.new(state: :idle))
        attr = page.find(".tui-sync-word")["data-controller"]
        expect(attr).to include("tui-sync-indicator")
        expect(attr).to include("tui-transition")
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
    end

    describe "per-state display value data-* attrs (JS contract)" do
      it "seeds idle, active, syncing, and disconnected Stimulus values" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css("[data-tui-sync-indicator-idle-value]")
        expect(page).to have_css("[data-tui-sync-indicator-active-value]")
        expect(page).to have_css("[data-tui-sync-indicator-syncing-value]")
        expect(page).to have_css("[data-tui-sync-indicator-disconnected-value]")
      end

      it "exposes the full display strings via data-attrs" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css(%([data-tui-sync-indicator-idle-value="#{idle_display}"]))
        expect(page).to have_css(%([data-tui-sync-indicator-active-value="#{active_display}"]))
        expect(page).to have_css(%([data-tui-sync-indicator-disconnected-value="#{disconnected_display}"]))
      end

      it "exposes the canonical mode attr" do
        render_inline(described_class.new(state: :idle))
        expect(page).to have_css('[data-tui-sync-indicator-mode-value="tst"]')
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

    describe "no legacy state names" do
      it "treats :synced as invalid and falls back to :idle" do
        expect(described_class.new(state: :synced).state).to eq(:idle)
      end

      it "treats :paused as invalid (paused state was dropped) and falls back to :idle" do
        expect(described_class.new(state: :paused).state).to eq(:idle)
      end
    end
  end

  # ─── :target mode — interactive per-panel ──────────────────────────
  describe ":target mode (interactive per-panel / per-sub-panel)" do
    subject(:rendered) do
      render_inline(described_class.new(
        mode: :target,
        target: "home.stack.meilisearch",
        parent_target: "home.stack",
        focusable_key: "meilisearch_sync"
      ))
    end

    let(:button) { rendered.css("button.tui-sync-word").first }

    it "renders a <button>, not a <span>, in :target mode" do
      expect(button).to be_present
      expect(rendered.css("span.tui-sync-word")).to be_empty
    end

    it "uses type=button so it never submits a surrounding form" do
      expect(button["type"]).to eq("button")
    end

    it "carries the canonical .tui-sync-word class + the --target modifier" do
      classes = button["class"].split
      expect(classes).to include("tui-sync-word")
      expect(classes).to include("tui-sync-word--target")
    end

    it "renders the SSR-default '[ ] sync' display string" do
      expect(button.text.strip).to eq("[ ] sync")
    end

    it "wires the tui-sync-indicator + tui-transition controllers" do
      attr = button["data-controller"]
      expect(attr).to include("tui-sync-indicator")
      expect(attr).to include("tui-transition")
    end

    it "binds click + Enter + Space to the toggle action" do
      action = button["data-action"].to_s
      expect(action).to include("click->tui-sync-indicator#toggle")
      expect(action).to include("keydown.enter->tui-sync-indicator#toggle")
      expect(action).to include("keydown.space->tui-sync-indicator#toggle")
    end

    it "emits the target value data attr" do
      expect(button["data-tui-sync-indicator-target-value"]).to eq("home.stack.meilisearch")
    end

    it "emits the parent-target value data attr for inheritance resolution" do
      expect(button["data-tui-sync-indicator-parent-target-value"]).to eq("home.stack")
    end

    it "emits the canonical mode attr = target" do
      expect(button["data-tui-sync-indicator-mode-value"]).to eq("target")
    end

    it "emits the focusable hooks when focusable_key is provided" do
      expect(button["data-tui-focusable"]).to eq("meilisearch_sync")
      expect(button["data-tui-focusable-key"]).to eq("meilisearch_sync")
      expect(button["data-tui-focusable-style"]).to eq("action")
    end

    it "OMITS the top-status-bar target attr (that's :tst-only)" do
      expect(button["data-tui-status-bar-target"]).to be_nil
    end

    it "carries an aria-label" do
      expect(button["aria-label"]).to be_present
    end

    describe "panel-level :target render (no parent_target)" do
      subject(:rendered) do
        render_inline(described_class.new(
          mode: :target,
          target: "home.stack",
          focusable_key: "stack_sync"
        ))
      end

      let(:button) { rendered.css("button.tui-sync-word").first }

      it "OMITS the parent-target data attr when none is provided" do
        expect(button["data-tui-sync-indicator-parent-target-value"]).to be_nil
      end

      it "still emits the direct target value" do
        expect(button["data-tui-sync-indicator-target-value"]).to eq("home.stack")
      end
    end

    describe ":target render with no focusable_key" do
      subject(:rendered) do
        render_inline(described_class.new(mode: :target, target: "home.something"))
      end

      let(:button) { rendered.css("button.tui-sync-word").first }

      it "OMITS the focusable data attrs entirely" do
        expect(button["data-tui-focusable"]).to be_nil
        expect(button["data-tui-focusable-key"]).to be_nil
        expect(button["data-tui-focusable-style"]).to be_nil
      end
    end

    describe "Symbol target args" do
      subject(:rendered) do
        render_inline(described_class.new(mode: :target, target: :"home.stack", parent_target: :"home"))
      end

      let(:button) { rendered.css("button.tui-sync-word").first }

      it "stringifies the target attr" do
        expect(button["data-tui-sync-indicator-target-value"]).to eq("home.stack")
      end

      it "stringifies the parent_target attr" do
        expect(button["data-tui-sync-indicator-parent-target-value"]).to eq("home")
      end
    end
  end

  # ─── shared helpers ────────────────────────────────────────────────
  describe "word helpers" do
    let(:component) { described_class.new }

    it "word_idle returns the full idle display string" do
      expect(component.word_idle).to eq(idle_display)
    end

    it "word_active returns the full active display string" do
      expect(component.word_active).to eq(active_display)
    end

    it "word_disconnected returns the full disconnected display string" do
      expect(component.word_disconnected).to eq(disconnected_display)
    end
  end

  describe "CSS class hook" do
    it "carries the .tui-sync-word class in :tst mode" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(".tui-sync-word")
    end

    it "carries the .tui-sync-word class in :target mode" do
      render_inline(described_class.new(mode: :target, target: "x.y"))
      expect(page).to have_css(".tui-sync-word")
    end
  end
end
