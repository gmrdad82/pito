require "rails_helper"

RSpec.describe Tui::SyncIndicatorComponent, type: :component do
  describe "default render" do
    it "renders an idle indicator (green dot + 'synced' word) when no kwargs" do
      render_inline(described_class.new)

      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
      expect(page).to have_no_css(".sb-sync-target")
    end
  end

  describe "state variants" do
    it ":idle -> green dot + idle word, no target" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
    end

    it ":syncing -> amber dot + syncing word, no target rendered even if passed" do
      render_inline(described_class.new(state: :syncing, target: "channels"))
      expect(page).to have_css(".sb-sync-dot--amber", text: "●")
      expect(page).to have_css(".sb-sync-word--syncing", text: "syncing")
      expect(page).to have_no_css(".sb-sync-target")
    end

    it ":syncing_with_target -> amber dot + syncing word + target rendered" do
      render_inline(described_class.new(state: :syncing_with_target, target: "channels"))
      expect(page).to have_css(".sb-sync-dot--amber", text: "●")
      expect(page).to have_css(".sb-sync-word--syncing", text: "syncing")
      expect(page).to have_css(".sb-sync-target", text: "channels")
    end

    it ":syncing_with_target without target -> target hidden (graceful fallback)" do
      render_inline(described_class.new(state: :syncing_with_target))
      expect(page).to have_css(".sb-sync-dot--amber")
      expect(page).to have_no_css(".sb-sync-target")
    end

    it ":disconnected -> red ✗ + disconnected word" do
      render_inline(described_class.new(state: :disconnected))
      expect(page).to have_css(".sb-sync-dot--red", text: "✗")
      expect(page).to have_css(".sb-sync-word--disconnected", text: "disconnected")
    end

    it "falls back to :idle when an unknown state is passed" do
      render_inline(described_class.new(state: :who_knows))
      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
    end
  end

  describe "Stimulus targets (cable wiring contract)" do
    it "carries data-tui-status-bar-target attrs on dot + word + sync container" do
      render_inline(described_class.new(state: :idle))
      expect(page).to have_css('[data-tui-status-bar-target="sync"]')
      expect(page).to have_css('[data-tui-status-bar-target="syncDot"]')
      expect(page).to have_css('[data-tui-status-bar-target="syncWord"]')
    end

    it "carries data-tui-status-bar-target=syncTarget when target is visible" do
      render_inline(described_class.new(state: :syncing_with_target, target: "channels"))
      expect(page).to have_css('[data-tui-status-bar-target="syncTarget"]')
    end
  end

  describe "edge cases" do
    it "treats blank string target as absent" do
      render_inline(described_class.new(state: :syncing_with_target, target: ""))
      expect(page).to have_no_css(".sb-sync-target")
    end

    it "accepts a string state (coerced to symbol)" do
      render_inline(described_class.new(state: "disconnected"))
      expect(page).to have_css(".sb-sync-dot--red", text: "✗")
    end
  end
end
