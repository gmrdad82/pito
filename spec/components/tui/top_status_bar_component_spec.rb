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

  # Wave 2A (2026-05-22) — SyncIndicator went glyph-free + word-only; root
  # class is `.tui-sync-word`. Legacy `.sb-sync` / `.sb-sync-dot` span
  # markers no longer render.
  it "renders Tui::SyncIndicatorComponent (tui-sync-word span)" do
    render_inline(component)
    expect(page).to have_css("span.tui-sync-word")
  end

  # Phase 2 (2026-05-22) — SidekiqStatsComponent moved from TST to BST.
  # The TST no longer mounts the sidekiq VC; the `tui:sidekiq-changed`
  # event still fires from `tui-status-bar`, now consumed by the
  # BST-mounted sidekiq span.
  it "does NOT render Tui::SidekiqStatsComponent (moved to BST in Phase 2)" do
    render_inline(component)
    expect(page).not_to have_css("span.tui-sidekiq-stats")
    expect(page).not_to have_css(".tui-sidekiq-row")
    expect(page).not_to have_css(".tui-sidekiq-cell")
    expect(page).not_to have_css(".sb-sidekiq")
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
    # Wave 2A (2026-05-22) — the disconnected red indicator is now driven
    # by the tui-transition outlet's `.is-pink` class (toggled live by
    # tui_sync_indicator_controller). On initial SSR the VC renders the
    # base `.tui-sync-word` span; the JS controller flips classes after
    # `connect()`. So at SSR time we lock the root span + the data
    # values that seed the controller, not a static class.
    it "renders the tui-sync-word span when SSR is given a sync_state kwarg" do
      bar = described_class.new(section: "settings", sync_state: :disconnected)
      render_inline(bar)
      expect(page).to have_css("span.tui-sync-word")
    end
  end

  describe "sidekiq stats delegation" do
    # Phase 2 (2026-05-22) — SidekiqStats is no longer mounted in the
    # TST. Even when callers pass `sidekiq_stats:`, the TST does not
    # render the VC; the BST owns it now. The kwarg remains accepted
    # for backward compatibility (no-op in the TST).
    it "does NOT render any sidekiq element even when sidekiq_stats kwarg is passed" do
      bar = described_class.new(section: "settings", sidekiq_stats: { busy: 0, enqueued: 0, retry: 3 })
      render_inline(bar)
      expect(page).not_to have_css("span.tui-sidekiq-stats")
      expect(page).not_to have_css(".tui-sidekiq-cell")
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
        # 2026-05-22 (Phase 3 drift fix) — actual var is `_pulseTimer`
        # (underscore-prefixed); spec regex updated to match the lived
        # source. The pattern still locks the contract: clearTimeout on
        # the existing timer immediately followed by a new setTimeout.
        expect(js_source).to match(/clearTimeout\(this\._pulseTimer\)[\s\S]+?setTimeout/)
      end
    end
  end
end
