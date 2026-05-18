require "rails_helper"

# Static-source structural lock for the `ownership-cascade` Stimulus
# controller (`app/javascript/controllers/ownership_cascade_controller.js`).
#
# Rack_test has no JS engine, so the runtime cascade can't be exercised
# directly via Capybara. What we CAN lock is the source text of the
# controller — handler method names, target declarations, and the
# specific cascade rules (mutual-exclusivity of `played`, auto-tick of
# `owned`, auto-untick of `played` on owned-off). Catches refactor
# breakage where someone renames a handler, drops a target, or silently
# changes the cascade semantics. The server-side cascade in
# `Games::OwnershipTogglesController` is the authoritative source of
# truth for the DB state; this spec only protects the optimistic
# client-side mirror.
RSpec.describe "OwnershipCascade Stimulus controller (static source)", type: :system do
  before { driven_by(:rack_test) }

  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/ownership_cascade_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares `owned` and `played` as Stimulus targets" do
      expect(controller_source).to match(
        /static\s+targets\s*=\s*\[\s*"owned"\s*,\s*"played"\s*\]/
      )
    end
  end

  describe "playedChanged handler" do
    it "defines the playedChanged(event) handler" do
      expect(controller_source).to match(/playedChanged\s*\(\s*event\s*\)\s*\{/)
    end

    it "reads the per-platform slug from `data-ownership-cascade-platform`" do
      # The cascade keys off this dataset attribute on every checkbox so
      # the mutual-exclusivity and auto-tick scans can compare platforms.
      # Both handlers read it via `dataset.ownershipCascadePlatform`.
      expect(controller_source).to match(/cb\.dataset\.ownershipCascadePlatform/)
    end

    it "iterates other played targets to enforce mutual exclusivity" do
      # The mutual-exclusivity scan walks `this.playedTargets` and
      # unticks every checkbox whose platform slug differs from the one
      # the user just flipped on.
      expect(controller_source).to match(
        /this\.playedTargets\.forEach\(\s*\(\s*other\s*\)\s*=>/
      )
      expect(controller_source).to match(/other\.checked\s*=\s*false/)
    end

    it "auto-ticks the owned checkbox for the same platform" do
      # When the user flips `played` ON, the matching `owned` checkbox
      # for the same platform slug is auto-checked.
      expect(controller_source).to match(
        /this\.ownedTargets\.find\(\s*\(\s*o\s*\)\s*=>\s*o\.dataset\.ownershipCascadePlatform/
      )
      expect(controller_source).to match(
        /ownedForThisPlatform\.checked\s*=\s*true/
      )
    end

    it "submits the cascaded form via requestSubmit" do
      # Each cascade-triggered checkbox flip requestSubmit()s its own
      # form so Turbo lands the matching PATCH on the server. The
      # function-typeof guard prevents older browsers from crashing.
      expect(controller_source).to match(
        /form\.requestSubmit\(\)/
      )
      expect(controller_source).to match(
        /typeof\s+form\.requestSubmit\s*===\s*"function"/
      )
    end
  end

  describe "ownedChanged handler" do
    it "defines the ownedChanged(event) handler" do
      expect(controller_source).to match(/ownedChanged\s*\(\s*event\s*\)\s*\{/)
    end

    it "no-ops when the owned checkbox flips ON (only OFF cascades)" do
      # The handler must early-return when `cb.checked` is true — only
      # flipping owned OFF cascades to played. Lock the guard literal so
      # a refactor that inverts the polarity is caught.
      expect(controller_source).to match(
        /ownedChanged\([^}]*if\s*\(\s*cb\.checked\s*\)\s*return/m
      )
    end

    it "auto-unticks the played checkbox for the same platform" do
      # When the user flips `owned` OFF, the matching `played` checkbox
      # for the same platform slug is auto-unchecked (you cannot be
      # playing on a platform you no longer own).
      expect(controller_source).to match(
        /this\.playedTargets\.find\(\s*\(\s*p\s*\)\s*=>\s*p\.dataset\.ownershipCascadePlatform/
      )
      expect(controller_source).to match(
        /playedForThisPlatform\.checked\s*=\s*false/
      )
    end
  end

  describe "visual sync helper" do
    it "syncs the wrapper label's modifier class with checkbox state" do
      # Without this private helper the green `--owned` / `--played`
      # tint would stay stale until the Turbo redirect re-renders the
      # page. The helper is invoked from both cascade branches with the
      # matching BEM modifier class.
      expect(controller_source).to match(/#syncToggleClass\(/)
      expect(controller_source).to include("ownership-matrix__toggle--played")
      expect(controller_source).to include("ownership-matrix__toggle--owned")
    end
  end
end
