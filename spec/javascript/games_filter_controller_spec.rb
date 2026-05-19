require "rails_helper"

# 2026-05-18 (Wave F consolidation) — static-source structural lock for the
# `games-filter` Stimulus controller
# (`app/javascript/controllers/games_filter_controller.js`).
#
# rack_test has no JS engine; the filter chip cascade, the
# default-checked diff, and the `history.replaceState` URL update can't
# be exercised through Capybara. Lock the controller's source instead:
# target declarations, the wired action handler, the cascade tables,
# the platform-mutex `played` rule, and the URL canonicalisation.
#
# Architecture references the spec is locking:
#   - Phase 27 v2 spec 06 + ADR 0013 (cascade rules)
#   - 2026-05-17 user lock: bare `/games` matches the default-checked
#     set (universe minus `played`); `played` is an explicit opt-in.
#   - 2026-05-17 PC store collapse: `gog` + `epic` retired; PC = Steam.
#
# A future refactor that drops any of these behaviors breaks this spec
# loudly, which is the entire point.
RSpec.describe "games_filter_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/games_filter_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares `chip` as a Stimulus target" do
      expect(controller_source).to match(
        /static\s+targets\s*=\s*\[\s*"chip"\s*\]/
      )
    end

    it "declares `universe`, `defaultChecked`, `requestPath`, and `frameId` values" do
      # The four declared values cover: the full token order (universe),
      # the bare-/games default-checked set (defaultChecked), the
      # request-path prefix (requestPath = "/games"), and the Turbo
      # Frame id (`games_listing`). Dropping any of them breaks either
      # the canonical URL or the Turbo refresh.
      values_block = controller_source[/static\s+values\s*=\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(values_block).to match(/universe:\s*Array/)
      expect(values_block).to match(/defaultChecked:\s*Array/)
      expect(values_block).to match(/requestPath:\s*String/)
      expect(values_block).to match(/frameId:\s*String/)
    end
  end

  describe "cascade tables" do
    it "lists the three PC platform tokens (Steam = PS = Switch — gog/epic dropped)" do
      # 2026-05-17 PC store collapse: only `ps`, `switch`, `steam`
      # remain. A future regression that re-introduces gog or epic
      # here would silently bring them back into the cascade.
      expect(controller_source).to match(
        /PLATFORM_TOKENS\s*=\s*\[\s*"ps"\s*,\s*"switch"\s*,\s*"steam"\s*\]/
      )
      expect(controller_source).not_to match(/PLATFORM_TOKENS[^=]*=\s*\[[^\]]*"gog"/),
        "PLATFORM_TOKENS must not list `gog` (retired 2026-05-17)"
      expect(controller_source).not_to match(/PLATFORM_TOKENS[^=]*=\s*\[[^\]]*"epic"/),
        "PLATFORM_TOKENS must not list `epic` (retired 2026-05-17)"
    end

    it "encodes the DEPS map — `owned` requires `released`" do
      expect(controller_source).to match(/owned:\s*\[\s*"released"\s*\]/)
    end

    it "encodes the DEPS map — `played` requires `released + owned`" do
      expect(controller_source).to match(
        /played:\s*\[\s*"released"\s*,\s*"owned"\s*\]/
      )
    end
  end

  describe "toggle action handler" do
    it "defines `toggle(event)` as the wired-from-HTML action" do
      expect(controller_source).to match(/toggle\s*\(\s*event\s*\)\s*\{/)
    end

    it "preventDefaults to override the JS-off `<a href>` fallback navigation" do
      toggle_body = controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- cascade helpers)/m].to_s
      expect(toggle_body).to include("event.preventDefault()"),
        "expected toggle() to event.preventDefault() so the chip's " \
        "fallback href does not navigate when JS is on"
    end

    it "flips the clicked chip's checked state before running the cascade" do
      toggle_body = controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- cascade helpers)/m].to_s
      expect(toggle_body).to match(
        /this\.setChipState\(\s*chip\s*,\s*willCheck\s*\)/
      ),
        "expected toggle() to flip the clicked chip first via setChipState"
    end

    it "runs the CHECK cascade only when willCheck is true" do
      toggle_body = controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- cascade helpers)/m].to_s
      expect(toggle_body).to match(
        /if\s*\(\s*willCheck\s*\)\s*\{[\s\S]*?cascadeCheckParents\(\s*token\s*\)/m
      )
    end

    it "always runs the UNCHECK cascade after the click (steady-state sweep)" do
      toggle_body = controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- cascade helpers)/m].to_s
      expect(toggle_body).to include("this.enforceUncheckCascade()"),
        "expected toggle() to call enforceUncheckCascade() unconditionally " \
        "so the corrective sweep runs even when checking a chip"
    end

    it "updates the browser URL via history.replaceState (no full reload)" do
      toggle_body = controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- cascade helpers)/m].to_s
      expect(toggle_body).to match(
        /window\.history\.replaceState\(\s*null\s*,\s*""\s*,\s*url\s*\)/
      )
    end

    it "points the Turbo Frame's src at the new URL to re-fetch the listing" do
      toggle_body = controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- cascade helpers)/m].to_s
      expect(toggle_body).to match(
        /document\.getElementById\(\s*this\.frameIdValue\s*\)/
      )
      expect(toggle_body).to match(/frame\.src\s*=\s*url/)
    end
  end

  describe "cascadeCheckParents — `played` auto-checks released + owned + platforms" do
    let(:cascade_check_body) do
      # Slice from the method DECLARATION (with the opening brace) to
      # the next method-level declaration so the toggle() block — which
      # calls `cascadeCheckParents(token)` — doesn't shadow the lookup.
      controller_source[/cascadeCheckParents\s*\(\s*token\s*\)\s*\{[\s\S]*?(?=^\s{2}enforceUncheckCascade)/m].to_s
    end

    it "walks the DEPS list and force-checks each parent token" do
      expect(cascade_check_body).to match(
        /parents\.forEach\(\s*\(\s*parentToken\s*\)\s*=>/
      )
      expect(cascade_check_body).to match(
        /this\.setChipState\(\s*parentChip\s*,\s*true\s*\)/
      )
    end

    it "when token === played and no platform is checked, force-checks ALL platforms" do
      # The "at least ONE platform" rule is preserved from spec 06 —
      # when `played` is toggled on and zero platform chips are checked,
      # every platform chip is auto-checked so the filter still returns
      # results.
      expect(cascade_check_body).to match(/if\s*\(\s*token\s*===\s*"played"\s*\)/)
      expect(cascade_check_body).to match(
        /platformChips\.some\(\s*\(\s*c\s*\)\s*=>\s*\n?\s*c\.classList\.contains\(\s*"chip--active"\s*\)/m
      )
      expect(cascade_check_body).to match(
        /if\s*\(\s*!anyPlatformChecked\s*\)\s*\{[\s\S]*?platformChips\.forEach/m
      )
    end
  end

  describe "enforceUncheckCascade — transitive corrective sweep" do
    let(:enforce_body) do
      controller_source[/enforceUncheckCascade\s*\(\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ ---------- DOM helpers)/m].to_s
    end

    it "iterates until no chips change (steady-state loop)" do
      expect(enforce_body).to match(/while\s*\(\s*changed\s*&&\s*safety\s*>\s*0\s*\)/)
      expect(enforce_body).to match(/changed\s*=\s*false/)
      expect(enforce_body).to match(/changed\s*=\s*true/)
    end

    it "carries a safety cap so DEPS growth cannot livelock the loop" do
      expect(enforce_body).to match(/safety\s*=\s*5/)
      expect(enforce_body).to match(/safety\s*-=\s*1/)
    end

    it "force-unchecks a child whose parents are no longer all satisfied" do
      expect(enforce_body).to match(/Object\.entries\(\s*this\.constructor\.DEPS\s*\)/)
      expect(enforce_body).to match(/parents\.every\(\s*isChecked\s*\)/)
      expect(enforce_body).to match(
        /this\.setChipState\(\s*childChip\s*,\s*false\s*\)/
      )
    end

    it "unchecks `played` when every platform chip is off" do
      # The `played` chip needs ≥ 1 platform — when the user unchecks
      # the last platform, the corrective sweep must drop `played` to
      # match.
      expect(enforce_body).to match(/if\s*\(\s*isChecked\(\s*"played"\s*\)\s*\)/)
      expect(enforce_body).to match(
        /platformChips\(\)\.some\(\s*\(\s*c\s*\)\s*=>\s*\n?\s*c\.classList\.contains\(\s*"chip--active"\s*\)/m
      )
      expect(enforce_body).to match(/if\s*\(\s*!anyPlatform\s*\)/)
    end
  end

  describe "setChipState — DOM manipulation" do
    let(:set_chip_body) do
      controller_source[/setChipState\s*\(\s*chip\s*,\s*checked\s*\)\s*\{[\s\S]*?(?=^\s{2}chipFor)/m].to_s
    end

    it "toggles the `chip--active` CSS class to mirror the checked state" do
      expect(set_chip_body).to match(/chip\.classList\.add\(\s*"chip--active"\s*\)/)
      expect(set_chip_body).to match(/chip\.classList\.remove\(\s*"chip--active"\s*\)/)
    end

    it "rewrites the `.md-check-static` indicator to `[x]` or `[ ]`" do
      # The bracketed indicator is the visible affordance — the active
      # class only re-styles the chip; the `[x]` / `[ ]` token is the
      # primary signal in the design system's monospace face.
      expect(set_chip_body).to match(/querySelector\(\s*"\.md-check-static"\s*\)/)
      expect(set_chip_body).to match(/checked\s*\?\s*"\[x\]"\s*:\s*"\[\s\]"/)
    end
  end

  describe "currentCheckedTokens — stable URL ordering" do
    let(:current_body) do
      controller_source[/currentCheckedTokens\s*\(\s*\)\s*\{[\s\S]*?(?=^\s{2}canonicalUrl)/m].to_s
    end

    it "iterates the universeValue in declaration order to keep the CSV stable" do
      # Iterating in universe order means a `?filters=released,owned`
      # URL never silently rewrites to `?filters=owned,released` on a
      # re-toggle — bookmarks survive.
      expect(current_body).to match(/this\.universeValue\.filter/)
    end

    it "only includes tokens whose chip is marked `chip--active`" do
      expect(current_body).to match(/chip\.classList\.contains\(\s*"chip--active"\s*\)/)
    end
  end

  describe "canonicalUrl — default-set detection" do
    let(:canonical_body) do
      controller_source[/canonicalUrl\s*\(\s*checked\s*\)\s*\{[\s\S]*?(?=^\s{2}\/\/ True when)/m].to_s
    end

    it "returns the bare path when the checked set matches the default-checked set" do
      # 2026-05-17 user lock: bare `/games` corresponds to the default-
      # checked set (universe minus `played`), NOT to every chip being
      # checked. Adding `played` is an explicit opt-in.
      expect(canonical_body).to match(/if\s*\(\s*this\.matchesDefaultChecked\(\s*checked\s*\)\s*\)/)
      expect(canonical_body).to match(/return\s+path/)
    end

    it "emits `?filters=<csv>` when the checked set diverges from the default" do
      expect(canonical_body).to match(/const\s+csv\s*=\s*checked\.join\(\s*","\s*\)/)
      expect(canonical_body).to match(%r{return\s+`\$\{path\}\?filters=\$\{csv\}`})
    end

    it "defaults to `/games` when requestPathValue is empty" do
      expect(canonical_body).to match(/this\.requestPathValue\s*\|\|\s*"\/games"/)
    end
  end

  describe "matchesDefaultChecked — diff against the default set" do
    let(:matches_body) do
      # Last method in the file — slice from declaration to the
      # class-closing brace (single-char on its own line).
      controller_source[/matchesDefaultChecked\s*\(\s*checked\s*\)\s*\{[\s\S]*?\n\}/m].to_s
    end

    it "compares against `defaultCheckedValue` when present, falling back to `universeValue`" do
      # Legacy markup that doesn't ship the `default-checked` value
      # gets the prior "every chip checked" rule via the universeValue
      # fallback, so old templates don't break on a controller upgrade.
      expect(matches_body).to match(
        /this\.hasDefaultCheckedValue\s*\?\s*this\.defaultCheckedValue\s*:\s*this\.universeValue/
      )
    end

    it "returns false on a length mismatch (cheap early exit)" do
      expect(matches_body).to match(/checked\.length\s*!==\s*defaults\.length/)
    end

    it "returns true only when every default token appears in `checked` (order-insensitive)" do
      expect(matches_body).to match(
        /defaults\.every\(\s*\(\s*t\s*\)\s*=>\s*checked\.includes\(\s*t\s*\)\s*\)/
      )
    end
  end
end
