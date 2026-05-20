require "rails_helper"
require "sidekiq/api"

RSpec.describe Tui::TopStatusBarComponent, type: :component do
  # The 5 locked states from `tmp/demo-status-bar-final.html`. Each
  # `it` block exercises one state end-to-end against the rendered
  # DOM — class hooks, glyphs, and text content.
  describe "locked demo state variants" do
    it "V1 — /home idle: section accent class + green dot + idle word + all sidekiq muted" do
      render_inline(described_class.new(
        section: "home",
        version: "0.3.2-beta8",
        sidekiq_stats: { busy: 0, enqueued: 0, retry: 0, scheduled: 0 },
        sync_state: :idle
      ))

      expect(page).to have_css(".sb-version", text: "0.3.2-beta8")
      expect(page).to have_css(".sb-section", text: "home")
      expect(page).to have_no_css(".sb-page-tail")

      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
      expect(page).to have_no_css(".sb-sync-target")

      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "e0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
      expect(page).to have_no_css(".sb-sk-cell.sk-b")
      expect(page).to have_no_css(".sb-sk-cell.sk-e")
      expect(page).to have_no_css(".sb-sk-cell.sk-r")
    end

    it "V2 — /channels idle with retries: r3 pink + b0/e0 muted + idle synced" do
      render_inline(described_class.new(
        section: "channels",
        version: "0.3.2-beta8",
        sidekiq_stats: { busy: 0, enqueued: 0, retry: 3, scheduled: 0 },
        sync_state: :idle
      ))

      expect(page).to have_css(".sb-section", text: "channels")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "e0")
      expect(page).to have_css(".sb-sk-cell.sk-r", text: "r3")
      expect(page).to have_no_css(".sb-sk-cell.sk-zero", text: "r3")
      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
    end

    it "V3 — /games active progress: page tail + progress bar + amber syncing + b12/e33/r0 colored" do
      render_inline(described_class.new(
        section: "games",
        page: "Witcher 3: Wild Hunt",
        version: "0.3.2-beta8",
        sidekiq_stats: { busy: 12, enqueued: 33, retry: 0, scheduled: 0 },
        sync_state: :syncing_with_target,
        sync_target: "channels",
        progress: { current: 12, total: 33 }
      ))

      expect(page).to have_css(".sb-section", text: /games/)
      expect(page).to have_css(".sb-page-tail")
      expect(page).to have_css(".sb-page-name", text: "Witcher 3: Wild Hunt")

      expect(page).to have_css(".sb-progress-bar")
      expect(page).to have_css(".sb-progress-bar-filled", text: /▓+/)
      expect(page).to have_css(".sb-progress-bar-empty",  text: /░+/)
      expect(page).to have_css(".sb-progress-counter", text: "12/33")

      expect(page).to have_css(".sb-sync-dot--amber", text: "●")
      expect(page).to have_css(".sb-sync-word--syncing", text: "syncing")
      expect(page).to have_css(".sb-sync-target", text: "channels")

      expect(page).to have_css(".sb-sk-cell.sk-b", text: "b12")
      expect(page).to have_css(".sb-sk-cell.sk-e", text: "e33")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
    end

    it "V4 — /settings idle: orange section accent class + all quiet sidekiq muted + idle synced" do
      render_inline(described_class.new(
        section: "settings",
        version: "0.3.2-beta8",
        sidekiq_stats: { busy: 0, enqueued: 0, retry: 0, scheduled: 0 },
        sync_state: :idle
      ))

      expect(page).to have_css(".sb-section", text: "settings")
      expect(page).to have_no_css(".sb-page-tail")
      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "e0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
    end

    it "V5 — /channels disconnected: red ✗ + disconnected word + all sidekiq muted" do
      render_inline(described_class.new(
        section: "channels",
        version: "0.3.2-beta8",
        sidekiq_stats: { busy: 0, enqueued: 0, retry: 0, scheduled: 0 },
        sync_state: :disconnected
      ))

      expect(page).to have_css(".sb-section", text: "channels")
      expect(page).to have_css(".sb-sync-dot--red", text: "✗")
      expect(page).to have_no_css(".sb-sync-dot--green")
      expect(page).to have_css(".sb-sync-word--disconnected", text: "disconnected")
      expect(page).to have_no_css(".sb-progress-bar")
    end
  end

  describe ":(page) tail rendering" do
    it "is absent when page: is nil" do
      render_inline(described_class.new(section: "home"))
      expect(page).to have_no_css(".sb-page-tail")
      expect(page).to have_no_css(".sb-page-name")
    end

    it "is present and wraps the page name in :( ... )" do
      render_inline(described_class.new(section: "games", page: "Witcher 3: Wild Hunt"))
      tail = page.find(".sb-page-tail")
      expect(tail.text).to include(":(")
      expect(tail.text).to include(")")
      expect(tail).to have_css(".sb-page-name", text: "Witcher 3: Wild Hunt")
    end

    it "treats blank string as absent (no tail)" do
      render_inline(described_class.new(section: "games", page: ""))
      expect(page).to have_no_css(".sb-page-tail")
    end
  end

  describe "section accent class hook" do
    it "always emits `.sb-section` regardless of which section is passed" do
      %w[home channels games settings videos projects].each do |section|
        rendered = render_inline(described_class.new(section: section))
        expect(rendered.css(".sb-section").first&.text).to include(section),
          "expected .sb-section to render the section label for #{section}"
      end
    end

    it "renders the section label as the visible text of .sb-section" do
      render_inline(described_class.new(section: "channels"))
      expect(page).to have_css(".sb-section", text: "channels")
    end
  end

  describe "Sidekiq color states" do
    it "muted-zero (sk-zero) for any cell whose value is 0" do
      render_inline(described_class.new(
        section: "home",
        sidekiq_stats: { busy: 0, enqueued: 5, retry: 0, scheduled: 0 }
      ))
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-e",    text: "e5")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
    end

    it "applies sk-b / sk-e / sk-r when each value is positive" do
      render_inline(described_class.new(
        section: "home",
        sidekiq_stats: { busy: 1, enqueued: 2, retry: 4 }
      ))
      expect(page).to have_css(".sb-sk-cell.sk-b", text: "b1")
      expect(page).to have_css(".sb-sk-cell.sk-e", text: "e2")
      expect(page).to have_css(".sb-sk-cell.sk-r", text: "r4")
    end

    it "defaults stats to all-zero when sidekiq_stats: is nil" do
      render_inline(described_class.new(section: "home"))
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "e0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
    end

    it "accepts string-keyed hashes" do
      render_inline(described_class.new(
        section: "home",
        sidekiq_stats: { "busy" => 7, "enqueued" => 0, "retry" => 0 }
      ))
      expect(page).to have_css(".sb-sk-cell.sk-b", text: "b7")
    end
  end

  describe "sync state" do
    it ":idle -> green dot + idle word, no target" do
      render_inline(described_class.new(section: "home", sync_state: :idle))
      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
      expect(page).to have_no_css(".sb-sync-target")
    end

    it ":syncing -> amber dot + syncing word, no target" do
      render_inline(described_class.new(section: "home", sync_state: :syncing))
      expect(page).to have_css(".sb-sync-dot--amber", text: "●")
      expect(page).to have_css(".sb-sync-word--syncing", text: "syncing")
      expect(page).to have_no_css(".sb-sync-target")
    end

    it ":syncing_with_target -> amber dot + syncing word + target rendered" do
      render_inline(described_class.new(
        section: "home",
        sync_state: :syncing_with_target,
        sync_target: "channels"
      ))
      expect(page).to have_css(".sb-sync-dot--amber", text: "●")
      expect(page).to have_css(".sb-sync-word--syncing", text: "syncing")
      expect(page).to have_css(".sb-sync-target", text: "channels")
    end

    it ":syncing_with_target without sync_target -> target hidden (graceful fallback)" do
      render_inline(described_class.new(section: "home", sync_state: :syncing_with_target))
      expect(page).to have_css(".sb-sync-dot--amber")
      expect(page).to have_no_css(".sb-sync-target")
    end

    it ":disconnected -> red ✗ + disconnected word" do
      render_inline(described_class.new(section: "home", sync_state: :disconnected))
      expect(page).to have_css(".sb-sync-dot--red", text: "✗")
      expect(page).to have_css(".sb-sync-word--disconnected", text: "disconnected")
    end

    it "falls back to :idle when an unknown sync_state symbol is passed" do
      render_inline(described_class.new(section: "home", sync_state: :who_knows))
      expect(page).to have_css(".sb-sync-dot--green", text: "●")
      expect(page).to have_css(".sb-sync-word--idle", text: "synced")
    end
  end

  describe "progress segment" do
    it "renders the bar + counter when progress: is provided" do
      render_inline(described_class.new(
        section: "games",
        progress: { current: 12, total: 33 }
      ))
      expect(page).to have_css(".sb-progress-bar")
      expect(page).to have_css(".sb-progress-counter", text: "12/33")
    end

    it "omits the bar + counter when progress: is nil" do
      render_inline(described_class.new(section: "games"))
      expect(page).to have_no_css(".sb-progress-bar")
      expect(page).to have_no_css(".sb-progress-counter")
    end

    it "omits the bar when total is zero" do
      render_inline(described_class.new(section: "games", progress: { current: 0, total: 0 }))
      expect(page).to have_no_css(".sb-progress-bar")
    end

    it "renders an 8-character bar with proportional filled/empty split" do
      render_inline(described_class.new(
        section: "games",
        progress: { current: 4, total: 8 }
      ))
      filled = page.find(".sb-progress-bar-filled").text
      empty  = page.find(".sb-progress-bar-empty").text
      expect(filled.length + empty.length).to eq(described_class::PROGRESS_BAR_WIDTH)
      expect(filled).to eq("▓" * 4)
      expect(empty).to  eq("░" * 4)
    end

    it "clamps over-100% progress (current > total) to a fully-filled bar" do
      render_inline(described_class.new(
        section: "games",
        progress: { current: 99, total: 10 }
      ))
      filled = page.find(".sb-progress-bar-filled").text
      empty  = page.find(".sb-progress-bar-empty").text
      expect(filled).to eq("▓" * described_class::PROGRESS_BAR_WIDTH)
      expect(empty).to eq("")
    end
  end

  describe "data-* hooks for the Stimulus controller" do
    before do
      render_inline(described_class.new(
        section: "games",
        page: "Witcher 3: Wild Hunt",
        sidekiq_stats: { busy: 1, enqueued: 2, retry: 3 },
        sync_state: :syncing_with_target,
        sync_target: "channels",
        progress: { current: 1, total: 4 }
      ))
    end

    it "carries the cable channel name on the root element" do
      expect(page).to have_css('.sb-bar[data-cable-channel="pito:status_bar"]')
    end

    it "wires the Stimulus controller via data-controller=tui-status-bar" do
      expect(page).to have_css('.sb-bar[data-controller~="tui-status-bar"]')
    end

    it "marks the root with data-tui-status-bar-target=root" do
      expect(page).to have_css('.sb-bar[data-tui-status-bar-target="root"]')
    end

    it "marks the clock cell with a stimulus target attribute" do
      expect(page).to have_css('.sb-clock[data-tui-status-bar-target="clock"]')
    end

    it "marks every Sidekiq cell with a stimulus target attribute" do
      expect(page).to have_css('.sb-sk-cell[data-tui-status-bar-target="sidekiqBusy"]')
      expect(page).to have_css('.sb-sk-cell[data-tui-status-bar-target="sidekiqEnqueued"]')
      expect(page).to have_css('.sb-sk-cell[data-tui-status-bar-target="sidekiqRetry"]')
    end

    it "marks the sync dot + word + target with stimulus target attributes" do
      expect(page).to have_css('[data-tui-status-bar-target="syncDot"]')
      expect(page).to have_css('[data-tui-status-bar-target="syncWord"]')
      expect(page).to have_css('[data-tui-status-bar-target="syncTarget"]')
    end

    it "marks the progress bar + counter with stimulus target attributes" do
      expect(page).to have_css('[data-tui-status-bar-target="progressBar"]')
      expect(page).to have_css('[data-tui-status-bar-target="progressCounter"]')
    end
  end

  describe "helper integrations (ApplicationHelper)" do
    # Lightweight host object so we can drive the helpers without a
    # request cycle. The status bar's helper trio is pure (reads
    # `controller_path` + `action_name` + ivars); a tiny stub stands
    # in for the controller / view binding.
    let(:helper_host) do
      Class.new do
        include ApplicationHelper
        attr_accessor :controller_path, :action_name
      end.new
    end

    describe "#pito_version" do
      it "delegates to app_version (reads the VERSION file)" do
        expect(helper_host.pito_version).to eq(helper_host.app_version)
      end

      it "matches the VERSION file content (trimmed)" do
        expected = Rails.root.join("VERSION").read.strip
        expect(helper_host.pito_version).to eq(expected)
      end
    end

    describe "#current_page" do
      it "returns nil when no controller_path is present" do
        helper_host.controller_path = nil
        helper_host.action_name = "show"
        expect(helper_host.current_page).to be_nil
      end

      it "returns nil for index actions (section root, no sub-page)" do
        helper_host.controller_path = "channels"
        helper_host.action_name = "index"
        expect(helper_host.current_page).to be_nil
      end

      it "returns the game title for games#show" do
        helper_host.controller_path = "games"
        helper_host.action_name = "show"
        game = double("Game", title: "Witcher 3: Wild Hunt")
        helper_host.instance_variable_set(:@game, game)
        expect(helper_host.current_page).to eq("Witcher 3: Wild Hunt")
      end

      it "returns the channel title for channels#show" do
        helper_host.controller_path = "channels"
        helper_host.action_name = "show"
        channel = double("Channel", title: "Linus Tech Tips", handle: "@LinusTechTips")
        helper_host.instance_variable_set(:@channel, channel)
        expect(helper_host.current_page).to eq("Linus Tech Tips")
      end

      it "falls back to handle when channel title is blank" do
        helper_host.controller_path = "channels"
        helper_host.action_name = "show"
        channel = double("Channel", title: nil, handle: "@LinusTechTips")
        helper_host.instance_variable_set(:@channel, channel)
        expect(helper_host.current_page).to eq("@LinusTechTips")
      end

      it "returns the project name for projects#show" do
        helper_host.controller_path = "projects"
        helper_host.action_name = "show"
        project = double("Project", name: "Footage Q3")
        helper_host.instance_variable_set(:@project, project)
        expect(helper_host.current_page).to eq("Footage Q3")
      end

      it "returns nil for unsupported controllers" do
        helper_host.controller_path = "notifications"
        helper_host.action_name = "show"
        expect(helper_host.current_page).to be_nil
      end
    end

    describe "#sidekiq_queue_stats" do
      it "returns a hash with the four expected keys" do
        allow(Sidekiq::Stats).to receive(:new).and_return(
          double("Stats", workers_size: 1, enqueued: 2, retry_size: 3, scheduled_size: 4)
        )
        expect(helper_host.sidekiq_queue_stats).to eq(
          busy: 1, enqueued: 2, retry: 3, scheduled: 4
        )
      end

      it "swallows Sidekiq errors and returns zeros (never blocks rendering)" do
        allow(Sidekiq::Stats).to receive(:new).and_raise(StandardError, "boom")
        expect(helper_host.sidekiq_queue_stats).to eq(
          busy: 0, enqueued: 0, retry: 0, scheduled: 0
        )
      end
    end
  end
end
