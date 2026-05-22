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

    # 2026-05-22 (cable routing refactor) — lock the JS-side
    # KIND_HANDLERS registry shape via static analysis of the controller
    # source. The Ruby suite cannot execute JS, but it CAN assert the
    # canonical kinds + the generic activity event name are present so
    # any rename in the JS layer surfaces here at test time.
    describe "KIND_HANDLERS registry contract (static JS source check)" do
      let(:js_source) do
        Rails.root.join("app/javascript/controllers/tui_status_bar_controller.js").read
      end

      it "exports KIND_HANDLERS as a frozen registry" do
        expect(js_source).to match(/export const KIND_HANDLERS = Object\.freeze/)
      end

      it "registers the canonical kind: sync" do
        expect(js_source).to match(/^\s*sync:\s+\{ event: "tui:sync-changed"/)
      end

      it "registers the canonical kind: sidekiq" do
        expect(js_source).to match(/^\s*sidekiq:\s+\{ event: "tui:sidekiq-changed"/)
      end

      it "registers the canonical kind: notifications" do
        expect(js_source).to match(/^\s*notifications:\s+\{ event: "tui:notifications-changed"/)
      end

      it "registers the legacy 'data' alias mapping to sidekiq" do
        expect(js_source).to match(/^\s*data:\s+\{ alias: "sidekiq"/)
      end

      it "exports the generic ACTIVITY_EVENT name" do
        expect(js_source).to match(/export const ACTIVITY_EVENT = "tui:cable-activity"/)
      end

      it "fires the activity event on every received message (before kind resolution)" do
        # The receive() method must dispatch ACTIVITY_EVENT before the
        # kind-specific fan-out. Regression test: if a future refactor
        # gates ACTIVITY_EVENT behind `if (handler)`, activity-aware
        # listeners (sync indicator pulse) stop pulsing on unknown kinds.
        expect(js_source).to match(
          /dispatchEvent\(new CustomEvent\(ACTIVITY_EVENT[\s\S]+?let handler = KIND_HANDLERS\[kind\]/
        )
      end
    end

    # 2026-05-22 — Lock the SyncIndicator activity-pulse contract via
    # static analysis of the child controller source. PULSE_MS is the
    # locked debounce window; if anyone changes the constant the spec
    # surfaces the drift.
    describe "SyncIndicator activity-pulse contract (static JS source check)" do
      let(:js_source) do
        Rails.root.join("app/javascript/controllers/tui_sync_indicator_controller.js").read
      end

      it "locks PULSE_MS to 400" do
        expect(js_source).to match(/static PULSE_MS = 400/)
      end

      it "listens for tui:cable-activity in connect()" do
        expect(js_source).to match(/addEventListener\("tui:cable-activity"/)
      end

      it "honors tui:sync-changed for the disconnected state only" do
        expect(js_source).to match(/addEventListener\("tui:sync-changed"/)
        expect(js_source).to match(/if \(state === "disconnected"\)/)
      end

      it "re-arms the pulse timer on every activity event" do
        expect(js_source).to match(/clearTimeout\(this\.pulseTimer\)[\s\S]+?setTimeout/)
      end
    end
  end
end
