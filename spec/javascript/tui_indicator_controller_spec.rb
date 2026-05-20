require "rails_helper"

# Beta 4 — Phase F2. Static-source structural lock for the
# `tui-indicator` Stimulus controller
# (`app/javascript/controllers/tui_indicator_controller.js`).
#
# Mirrors the `tui_status_bar_controller_spec.rb` discipline: rack_test
# has no JS engine, so the actual interval-driven frame advance can't
# be exercised at runtime here. What we CAN lock is the source text —
# the FRAMES table, the CADENCE_MS table, lifecycle hooks, and the
# tick() advance math. Drift in any of these silently changes the feel
# of every indicator in the app.
RSpec.describe "tui_indicator_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/tui_indicator_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "imports Controller from @hotwired/stimulus" do
      expect(controller_source).to match(
        /import\s*\{\s*Controller\s*\}\s*from\s*"@hotwired\/stimulus"/
      )
    end
  end

  describe "Stimulus values" do
    let(:values_block) do
      controller_source[/static\s+values\s*=\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "declares `variant` as a String value" do
      expect(values_block).to match(/variant:\s*String/)
    end

    it "declares `startOffset` as a Number value with default 0" do
      expect(values_block).to match(/startOffset:\s*\{\s*type:\s*Number,\s*default:\s*0\s*\}/)
    end
  end

  describe "FRAMES table" do
    let(:frames_block) do
      controller_source[/static\s+FRAMES\s*=\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "exposes the 6-frame bounce_equals sequence" do
      expect(frames_block).to include('bounce_equals: ["=---", "-=--", "--=-", "---=", "--=-", "-=--"]')
    end

    it "exposes the 10-frame braille sequence" do
      expect(frames_block).to include('braille: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]')
    end
  end

  describe "CADENCE_MS table" do
    let(:cadence_block) do
      controller_source[/static\s+CADENCE_MS\s*=\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "locks bounce_equals cadence at 120ms" do
      expect(cadence_block).to match(/bounce_equals:\s*120/)
    end

    it "locks braille cadence at 100ms" do
      expect(cadence_block).to match(/braille:\s*100/)
    end
  end

  describe "connect() — frame seeding + interval scheduling" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "reads frames from the FRAMES table keyed by variantValue" do
      expect(connect_body).to match(/this\.constructor\.FRAMES\[\s*this\.variantValue\s*\]/)
    end

    it "bails early when variant has no frames mapping" do
      expect(connect_body).to match(/if\s*\(\s*!frames\s*\)\s*return/)
    end

    it "seeds the frame index from startOffsetValue modulo frames.length" do
      expect(connect_body).to match(/this\.idx\s*=\s*this\.startOffsetValue\s*%\s*frames\.length/)
    end

    it "reads cadence from the CADENCE_MS table keyed by variantValue" do
      expect(connect_body).to match(/this\.constructor\.CADENCE_MS\[\s*this\.variantValue\s*\]/)
    end

    it "writes the seeded frame to textContent before scheduling the interval" do
      expect(connect_body).to match(/this\.element\.textContent\s*=\s*this\.frames\[\s*this\.idx\s*\]/)
    end

    it "schedules tick() via setInterval at the variant cadence" do
      expect(connect_body).to match(/this\.timer\s*=\s*setInterval\(\s*\(\s*\)\s*=>\s*this\.tick\(\s*\),\s*cadence\s*\)/)
    end
  end

  describe "disconnect() — clean teardown" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "guards clearInterval behind a timer presence check" do
      expect(disconnect_body).to match(/if\s*\(\s*this\.timer\s*\)/)
      expect(disconnect_body).to include("clearInterval(this.timer)")
    end

    it "nulls the cached timer so a re-mount starts clean" do
      expect(disconnect_body).to match(/this\.timer\s*=\s*null/)
    end
  end

  describe "tick() — frame advance" do
    let(:tick_body) do
      controller_source[/tick\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a tick() method" do
      expect(controller_source).to match(/tick\s*\(\s*\)\s*\{/)
    end

    it "advances idx by 1 modulo frames.length (wraps cleanly)" do
      expect(tick_body).to match(/this\.idx\s*=\s*\(\s*this\.idx\s*\+\s*1\s*\)\s*%\s*this\.frames\.length/)
    end

    it "writes the next frame to textContent" do
      expect(tick_body).to match(/this\.element\.textContent\s*=\s*this\.frames\[\s*this\.idx\s*\]/)
    end
  end
end
