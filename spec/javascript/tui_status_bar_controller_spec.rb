require "rails_helper"

# Beta 4 — Phase F1 Lane C. Static-source structural lock for the
# `tui-status-bar` Stimulus controller
# (`app/javascript/controllers/tui_status_bar_controller.js`).
#
# Mirrors the `stack_stats_live_controller_spec.rb` discipline:
# rack_test has no JS engine, so the actual ActionCable subscription +
# DOM patches can't be exercised at runtime here. What we CAN lock is
# the source text — target declarations, lifecycle wiring, payload
# branch coverage, and the contract between this controller (Lane C),
# `Tui::TopStatusBarComponent` (Lane B), and `StatusBarChannel` (Lane
# A).
#
# Drift in any of these (renamed target, dropped subscribe teardown,
# missed payload `kind`) silently breaks the top status bar and the
# user sees a stale or dark indicator with no error.
RSpec.describe "tui_status_bar_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/tui_status_bar_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "imports createConsumer from @rails/actioncable" do
      expect(controller_source).to match(
        /import\s*\{\s*createConsumer\s*\}\s*from\s*"@rails\/actioncable"/
      )
    end
  end

  describe "Stimulus targets" do
    # Every target name in Lane B's `top_status_bar_component.html.erb`
    # must appear here. Adding / renaming a `data-tui-status-bar-target`
    # on the component must be mirrored in this list or the
    # corresponding `hasXxxTarget` guard makes the controller silently
    # no-op for that cell.
    %w[
      root
      sync syncDot syncWord syncTarget
      progressBar progressCounter
      sidekiq sidekiqBusy sidekiqEnqueued sidekiqRetry
      clock
    ].each do |target_name|
      it "declares `#{target_name}` as a Stimulus target" do
        expect(controller_source).to match(/"#{Regexp.escape(target_name)}"/),
          "expected `#{target_name}` in the static targets array"
      end
    end

    it "declares the targets via `static targets = [...]`" do
      expect(controller_source).to match(/static\s+targets\s*=\s*\[/)
    end
  end

  describe "connect() — clock + cable wiring" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "starts the live clock" do
      expect(connect_body).to include("this.startClock()"),
        "expected connect() to kick off the 1Hz wall-clock"
    end

    it "creates an ActionCable consumer via createConsumer()" do
      expect(connect_body).to include("createConsumer()"),
        "expected connect() to instantiate the ActionCable consumer"
    end

    it "subscribes to the StatusBarChannel" do
      expect(connect_body).to match(/channel:\s*"StatusBarChannel"/),
        "expected connect() to subscribe to StatusBarChannel by name"
    end

    it "wires the connected / disconnected / received callbacks" do
      expect(connect_body).to match(/connected:\s*\(\s*\)\s*=>\s*this\.onConnected\(\s*\)/)
      expect(connect_body).to match(/disconnected:\s*\(\s*\)\s*=>\s*this\.onDisconnected\(\s*\)/)
      expect(connect_body).to match(/received:\s*\(\s*data\s*\)\s*=>\s*this\.applyPayload\(\s*data\s*\)/)
    end

    it "caches both the consumer and subscription on the instance" do
      expect(connect_body).to match(/this\.consumer\s*=/)
      expect(connect_body).to match(/this\.subscription\s*=/)
    end
  end

  describe "disconnect() — clean teardown" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "stops the live clock" do
      expect(disconnect_body).to include("this.stopClock()"),
        "expected disconnect() to clear the 1Hz interval"
    end

    it "guards unsubscribe behind a subscription presence check" do
      expect(disconnect_body).to match(/if\s*\(\s*this\.subscription\s*\)/)
      expect(disconnect_body).to include("this.subscription.unsubscribe()")
    end

    it "guards consumer.disconnect() behind a presence check" do
      expect(disconnect_body).to match(/if\s*\(\s*this\.consumer\s*\)/)
      expect(disconnect_body).to include("this.consumer.disconnect()")
    end

    it "nulls cached refs so a re-mount starts clean" do
      expect(disconnect_body).to match(/this\.subscription\s*=\s*null/)
      expect(disconnect_body).to match(/this\.consumer\s*=\s*null/)
    end
  end

  describe "live clock" do
    it "ticks every 1000ms via setInterval" do
      body = controller_source[/startClock\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/setInterval\([^,]+,\s*1000\)/),
        "expected startClock() to schedule a 1Hz interval"
    end

    it "renders weekday + month-day · HH:MM:SS in updateClock()" do
      body = controller_source[/updateClock\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      # The clock string format is locked: `Mon, May 20 · 14:23:45`.
      # Drifting the separator (· vs |) or the abbreviation set silently
      # changes every page's status bar.
      expect(body).to include("Mon"), "expected weekday abbreviation set"
      expect(body).to include("May"), "expected month abbreviation set"
      expect(body).to match(/`.*·.*`/), "expected `·` separator between date and time"
      expect(body).to match(/padStart\(\s*2,\s*"0"\s*\)/), "expected HH/MM/SS zero-padding"
    end

    it "clears the interval and nulls the timer in stopClock()" do
      body = controller_source[/stopClock\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to include("clearInterval(this.clockTimer)")
      expect(body).to match(/this\.clockTimer\s*=\s*null/)
    end
  end

  describe "applyPayload — payload funnel" do
    let(:apply_body) do
      controller_source[/applyPayload\s*\(\s*data\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "bails early on a falsy payload" do
      expect(apply_body).to match(/if\s*\(\s*!data\s*\)\s*return/)
    end

    it "destructures kind + payload from the envelope" do
      expect(apply_body).to match(/const\s*\{\s*kind\s*,\s*payload\s*\}\s*=\s*data/)
    end

    %w[idle indeterminate progress complete error data].each do |kind|
      it "handles the `#{kind}` kind" do
        expect(apply_body).to match(/case\s+"#{kind}"\s*:/),
          "expected applyPayload to branch on kind=#{kind}"
      end
    end
  end

  describe "setSyncState — sync indicator state machine" do
    let(:body) do
      controller_source[/setSyncState\s*\(\s*state,\s*target\s*=\s*null\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as setSyncState(state, target = null)" do
      expect(controller_source).to match(/setSyncState\s*\(\s*state,\s*target\s*=\s*null\s*\)\s*\{/)
    end

    it "removes every sync-dot color modifier before re-applying" do
      %w[green amber red].each do |color|
        expect(body).to include("sb-sync-dot--#{color}"),
          "expected sb-sync-dot--#{color} to be referenced in the state reset"
      end
    end

    it "removes every sync-word state modifier before re-applying" do
      %w[idle syncing disconnected].each do |s|
        expect(body).to include("sb-sync-word--#{s}"),
          "expected sb-sync-word--#{s} to be referenced in the state reset"
      end
    end

    it "uses ● for connected states and ✗ for disconnected" do
      expect(body).to include("✗")
      expect(body).to include("●")
    end

    it "maps idle/syncing/disconnected to synced/syncing/disconnected words" do
      expect(body).to match(/idle:\s*"synced"/)
      expect(body).to match(/syncing:\s*"syncing"/)
      expect(body).to match(/disconnected:\s*"disconnected"/)
    end

    it "renders the optional sync target label only while syncing" do
      # The `syncTargetTarget` cell only carries a value when state ===
      # 'syncing' AND a target string was passed. Idle / disconnected
      # transitions must clear the cell so a stale `channels` label
      # doesn't outlast its sync.
      expect(body).to match(/state\s*===\s*"syncing"\s*&&\s*target/)
    end
  end

  describe "progress bar" do
    let(:show_body) do
      controller_source[/showProgressBar\s*\(\s*current,\s*total\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "exposes PROGRESS_BAR_WIDTH = 8 (matches component constant)" do
      expect(controller_source).to match(/static\s+PROGRESS_BAR_WIDTH\s*=\s*8/)
    end

    it "bails on missing targets or nullish values" do
      expect(show_body).to match(/if\s*\(\s*!this\.hasProgressBarTarget\s*\|\|\s*!this\.hasProgressCounterTarget\s*\)\s*return/)
      expect(show_body).to match(/if\s*\(\s*current\s*==\s*null\s*\|\|\s*total\s*==\s*null\s*\)\s*return/)
    end

    it "rejects non-positive totals (no division-by-zero, no negative bar)" do
      expect(show_body).to match(/totalInt\s*<=\s*0/)
    end

    it "uses filled `▓` and empty `░` glyphs" do
      expect(show_body).to include("▓")
      expect(show_body).to include("░")
    end

    it "constructs the bar via createElement (no innerHTML)" do
      # XSS hygiene: the bar is rebuilt via createElement + textContent,
      # never via innerHTML, so a future caller can't accidentally thread
      # user-supplied text into the cell.
      expect(show_body).to include('document.createElement("span")')
      # Reject any actual HTML-string assignment. The substring may
      # appear inside an explanatory comment, which is fine; what we
      # forbid is the `.<unsafe-prop> =` pattern.
      unsafe_prop = [ "inner", "HTML" ].join
      expect(show_body).not_to match(/\.#{unsafe_prop}\s*=/),
        "progress bar must use createElement + textContent (no HTML-string assignment)"
    end

    it "writes the counter as `current/total`" do
      expect(show_body).to match(/`\$\{currentInt\}\/\$\{totalInt\}`/)
    end

    it "hideProgressBar empties both cells" do
      body = controller_source[/hideProgressBar\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to include('this.progressBarTarget.textContent = ""')
      expect(body).to include('this.progressCounterTarget.textContent = ""')
    end
  end

  describe "Sidekiq cell updates" do
    let(:stats_body) do
      controller_source[/updateSidekiqStats\s*\(\s*stats\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end
    let(:cell_body) do
      controller_source[/updateSidekiqCell\s*\(\s*el,\s*letter,\s*value,\s*nonZeroClass\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "dispatches busy / enqueued / retry to their cells" do
      expect(stats_body).to match(/stats\.busy\s*!==\s*undefined.*sidekiqBusyTarget/m)
      expect(stats_body).to match(/stats\.enqueued\s*!==\s*undefined.*sidekiqEnqueuedTarget/m)
      expect(stats_body).to match(/stats\.retry\s*!==\s*undefined.*sidekiqRetryTarget/m)
    end

    it "writes `<letter><value>` to the cell" do
      expect(cell_body).to match(/`\$\{letter\}\$\{safe\}`/)
    end

    it "swaps `sk-zero` ↔ per-letter color class on zero / non-zero" do
      expect(cell_body).to match(/safe\s*===\s*0/)
      expect(cell_body).to include('el.classList.add("sk-zero")')
      expect(cell_body).to include("el.classList.remove(nonZeroClass)")
      expect(cell_body).to include('el.classList.remove("sk-zero")')
      expect(cell_body).to include("el.classList.add(nonZeroClass)")
    end
  end

  describe "cable lifecycle callbacks" do
    it "onConnected snaps the indicator to idle (green)" do
      body = controller_source[/onConnected\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/setSyncState\(\s*"idle"\s*\)/)
    end

    it "onDisconnected surfaces the red ✗ disconnected indicator" do
      body = controller_source[/onDisconnected\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/setSyncState\(\s*"disconnected"\s*\)/)
    end
  end
end
