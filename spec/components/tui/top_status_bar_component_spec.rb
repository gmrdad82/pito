# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::TopStatusBarComponent, type: :component do
  subject(:component) { described_class.new(section: "settings") }

  it "renders without raising" do
    expect { render_inline(component) }.not_to raise_error
  end

  it "renders the sb-bar root element with the Stimulus controller" do
    render_inline(component)
    expect(page).to have_css(".sb-bar[data-controller='tui-status-bar']")
  end

  it "renders Tui::AppVersionComponent (sb-version link)" do
    render_inline(component)
    expect(page).to have_css("a.sb-version")
  end

  it "renders Tui::BreadcrumbComponent (sb-section span)" do
    render_inline(component)
    expect(page).to have_css("span.sb-section")
  end

  it "renders Tui::SyncIndicatorComponent (sb-sync span)" do
    render_inline(component)
    expect(page).to have_css("span.sb-sync")
  end

  it "renders Tui::SidekiqStatsComponent (sb-sidekiq span)" do
    render_inline(component)
    expect(page).to have_css("span.sb-sidekiq")
  end

  it "renders Tui::DateTimeComponent (sb-clock span)" do
    render_inline(component)
    expect(page).to have_css("span.sb-clock")
  end

  describe "progress segment" do
    it "omits the progress bar when no progress kwarg is given" do
      render_inline(component)
      expect(page).not_to have_css(".sb-progress-bar")
    end

    it "renders the progress bar when a valid progress hash is given" do
      bar = described_class.new(section: "games", progress: { current: 4, total: 8 })
      render_inline(bar)
      expect(page).to have_css(".sb-progress-bar")
      expect(page).to have_css(".sb-progress-counter", text: "4/8")
    end

    it "omits the progress bar when total is 0" do
      bar = described_class.new(section: "games", progress: { current: 0, total: 0 })
      render_inline(bar)
      expect(page).not_to have_css(".sb-progress-bar")
    end
  end

  describe "sync state delegation" do
    it "passes :disconnected state to the SyncIndicatorComponent" do
      bar = described_class.new(section: "settings", sync_state: :disconnected)
      render_inline(bar)
      expect(page).to have_css(".sb-sync-dot--red")
    end
  end

  describe "sidekiq stats delegation" do
    it "passes non-zero retry count to SidekiqStatsComponent (sk-r class)" do
      bar = described_class.new(section: "settings", sidekiq_stats: { busy: 0, enqueued: 0, retry: 3 })
      render_inline(bar)
      expect(page).to have_css(".sb-sk-cell.sk-r")
    end
  end

  describe "cable wiring" do
    it "carries data-cable-channel attribute for ActionCable subscription" do
      render_inline(component)
      expect(page).to have_css("[data-cable-channel='pito:status_bar']")
    end
  end
end
