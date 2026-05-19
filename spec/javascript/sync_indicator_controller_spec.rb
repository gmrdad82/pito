require "rails_helper"

# 2026-05-19 (Wave B) — Static-source structural lock for the
# `sync-indicator` Stimulus controller
# (`app/javascript/controllers/sync_indicator_controller.js`).
#
# Rack_test has no JS engine, so the runtime DOM cycling of the
# `=---` → `-=--` → `--=-` → `---=` frames can't be exercised via
# Capybara. What we CAN lock here is the source text of the
# controller — Stimulus values declarations, the lifecycle hooks,
# the phaseOffset-respecting connect() seed, and the disconnect()
# timer teardown. Drift in any of these silently breaks the
# /games/:id resync loaders (genre line, kv-table date / dev / pub
# rows, summary block).
RSpec.describe "sync_indicator_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/sync_indicator_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end
  end

  describe "Stimulus values" do
    it "declares `frames` as an Array value" do
      expect(controller_source).to match(/frames:\s*Array/)
    end

    it "declares `interval` as a Number value with default 200" do
      expect(controller_source).to match(/interval:\s*\{\s*type:\s*Number,\s*default:\s*200\s*\}/)
    end

    # 2026-05-19 (Wave B) — `phaseOffset` lets multiple concurrent
    # indicators on the same page start at different positions in the
    # cycle so the page reads as a wave, not a single uniform pulse.
    it "declares `phaseOffset` as a Number value with default 0" do
      expect(controller_source).to match(/phaseOffset:\s*\{\s*type:\s*Number,\s*default:\s*0\s*\}/)
    end
  end

  describe "lifecycle wiring" do
    it "defines connect()" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "defines disconnect()" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "defines tick()" do
      expect(controller_source).to match(/tick\s*\(\s*\)\s*\{/)
    end
  end

  describe "phase-offset cycle seed" do
    it "reads phaseOffsetValue when seeding the initial frame index" do
      # The connect() body MUST initialize `this.frame` from
      # `this.phaseOffsetValue` (modulo cycle length) — otherwise the
      # offset attribute is silently ignored and every loader on the
      # page reads the same frame at the same time.
      expect(controller_source).to match(/this\.frame\s*=\s*[^\n]*phaseOffsetValue/)
    end

    it "modulos the offset by framesValue.length (no out-of-range index)" do
      expect(controller_source).to match(/phaseOffsetValue\s*%\s*length/)
    end

    it "falls back to frame 0 when framesValue is empty" do
      # Defensive — an empty frames array would otherwise compute
      # `0 % 0 = NaN` and break the first tick().
      expect(controller_source).to match(/length\s*>\s*0\s*\?\s*this\.phaseOffsetValue\s*%\s*length\s*:\s*0/)
    end
  end

  describe "ticking behavior" do
    it "uses setInterval with intervalValue" do
      # Match `setInterval(...)` whose argument list ends with
      # `, this.intervalValue)`. The first arg is a tick callback
      # (`() => this.tick()`) that itself contains parens, so a
      # `[^)]*` first-arg matcher fails — use a non-greedy `.*?`.
      expect(controller_source).to match(/setInterval\(.*?,\s*this\.intervalValue\)/)
    end

    it "patches `this.element.textContent` from framesValue" do
      expect(controller_source).to match(/this\.element\.textContent\s*=/)
      expect(controller_source).to match(/this\.framesValue\[\s*this\.frame\s*%\s*this\.framesValue\.length\s*\]/)
    end

    it "increments the frame counter on every tick" do
      expect(controller_source).to match(/this\.frame\+\+/)
    end

    it "no-ops the tick when framesValue is empty (defensive)" do
      expect(controller_source).to match(/if\s*\(\s*this\.framesValue\.length\s*===\s*0\s*\)\s*return/)
    end
  end

  describe "disconnect teardown" do
    it "clears the timer on disconnect" do
      expect(controller_source).to match(/clearInterval\s*\(\s*this\.timer\s*\)/)
    end

    it "nulls the timer reference after clearing" do
      expect(controller_source).to match(/this\.timer\s*=\s*null/)
    end
  end
end
