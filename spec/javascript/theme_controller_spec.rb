require "rails_helper"

# 2026-05-18 — Static-source structural lock for the `theme` Stimulus
# controller (`app/javascript/controllers/theme_controller.js`).
#
# Rack_test has no JS engine, so we can't actually flip the theme and
# inspect `document.documentElement.dataset.theme` via Capybara. What
# we CAN lock is the source text — the localStorage-only persistence
# story (Phase 29 dropped server-side theme storage), the
# system-preference fallback, the `applyTheme` recolor hook, and the
# disconnect() teardown of the media-query listener.
#
# A future refactor that re-introduces a server PATCH or drops the
# `prefers-color-scheme` matchMedia layer breaks this spec loudly,
# which is the intent.
RSpec.describe "theme_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/theme_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares `toggle` as the only Stimulus target" do
      expect(controller_source).to match(
        /static\s+targets\s*=\s*\[\s*"toggle"\s*\]/
      )
    end
  end

  describe "connect() — initial apply + system-preference listener" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "applies the resolved theme on connect (restores state)" do
      expect(connect_body).to include("this.applyTheme()"),
        "expected connect() to call applyTheme() so the cached/system " \
        "theme is restored on every controller mount"
    end

    it "caches the prefers-color-scheme MediaQueryList on the instance" do
      expect(connect_body).to match(
        /this\.mediaQuery\s*=\s*window\.matchMedia\(\s*"\(prefers-color-scheme:\s*dark\)"\s*\)/
      )
    end

    it "registers `change` on the media query, routed to onSystemChange" do
      expect(connect_body).to match(
        /this\.mediaQuery\.addEventListener\(\s*"change"\s*,\s*this\.onSystemChange\s*\)/
      )
    end
  end

  describe "disconnect() — clean teardown" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "removes the system-preference change listener using the SAME handler ref" do
      # Turbo morphs and controller re-mounts must not leak duplicate
      # `change` listeners on the prefers-color-scheme MediaQueryList.
      # Removal must use `this.onSystemChange` — the same bound ref
      # `connect()` registered.
      expect(disconnect_body).to match(
        /this\.mediaQuery\?\.removeEventListener\(\s*"change"\s*,\s*this\.onSystemChange\s*\)/
      )
    end
  end

  describe "toggle() — Stimulus action handler" do
    let(:toggle_body) do
      controller_source[/toggle\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines toggle(event)" do
      expect(controller_source).to match(/toggle\s*\(\s*event\s*\)\s*\{/)
    end

    it "preventDefaults to swallow the link / button activation" do
      # The [theme] affordance is rendered as a bracketed anchor. Without
      # preventDefault Turbo would attempt to navigate to `href="#"`.
      expect(toggle_body).to include("event.preventDefault()"),
        "expected toggle() to event.preventDefault()"
    end

    it "delegates to doToggle() (the no-event variant)" do
      # `doToggle()` is the actual flip — separating it means a future
      # keybind or programmatic flip can call doToggle directly without
      # having to fabricate a fake event.
      expect(toggle_body).to include("this.doToggle()"),
        "expected toggle() to delegate to this.doToggle()"
    end
  end

  describe "doToggle() — flips and persists" do
    let(:do_toggle_body) do
      controller_source[/doToggle\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines doToggle()" do
      expect(controller_source).to match(/doToggle\s*\(\s*\)\s*\{/)
    end

    it "computes the next theme from effectiveTheme()" do
      # The toggle bases the flip on what's CURRENTLY rendered (which
      # may have been resolved from the system preference), not on
      # what's in localStorage. A user who started on system-dark and
      # clicks [theme] expects to land on `light`, not on whatever was
      # last stored.
      expect(do_toggle_body).to include("this.effectiveTheme()"),
        "expected doToggle() to base `current` on effectiveTheme()"
      expect(do_toggle_body).to match(
        /next\s*=\s*current\s*===\s*"dark"\s*\?\s*"light"\s*:\s*"dark"/
      )
    end

    it "persists the next theme to localStorage under `pito-theme`" do
      # Phase 29 — localStorage ONLY, no server PATCH. The key is
      # `pito-theme` (project-namespaced).
      expect(do_toggle_body).to match(
        /localStorage\.setItem\(\s*"pito-theme"\s*,\s*next\s*\)/
      )
    end

    it "calls applyTheme() after persisting so the DOM updates immediately" do
      expect(do_toggle_body).to include("this.applyTheme()"),
        "expected doToggle() to call applyTheme() after writing localStorage"
    end
  end

  describe "applyTheme() — DOM patch + chart recolor hook" do
    let(:apply_body) do
      controller_source[/applyTheme\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines applyTheme()" do
      expect(controller_source).to match(/applyTheme\s*\(\s*\)\s*\{/)
    end

    it "writes the resolved theme onto <html data-theme=...>" do
      # `data-theme` on the root element is the single CSS-variable
      # switch the design system reads. Drift breaks every page.
      expect(apply_body).to match(
        /document\.documentElement\.setAttribute\(\s*"data-theme"\s*,\s*theme\s*\)/
      )
    end

    it "calls window.recolorCharts (when present) after a small delay" do
      # Charts re-resolve their colors from CSS variables, but Chart.js
      # caches the resolved values — the recolor hook re-reads them
      # after the data-theme attribute has flipped. The 50ms timeout
      # gives the browser one paint to apply the new CSS.
      expect(apply_body).to match(
        /if\s*\(\s*window\.recolorCharts\s*\)\s*setTimeout\(\s*window\.recolorCharts\s*,\s*50\s*\)/
      )
    end
  end

  describe "effectiveTheme() — localStorage with system-preference fallback" do
    let(:eff_body) do
      controller_source[/effectiveTheme\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines effectiveTheme()" do
      expect(controller_source).to match(/effectiveTheme\s*\(\s*\)\s*\{/)
    end

    it "reads `pito-theme` from localStorage first" do
      expect(eff_body).to match(/localStorage\.getItem\(\s*"pito-theme"\s*\)/)
    end

    it "returns the stored value only when it's `light` or `dark`" do
      # A corrupted localStorage entry must not propagate — the
      # fallback to system preference catches anything else.
      expect(eff_body).to match(
        /stored\s*===\s*"light"\s*\|\|\s*stored\s*===\s*"dark"/
      )
    end

    it "falls back to `prefers-color-scheme: dark` when no stored value" do
      expect(eff_body).to match(
        /window\.matchMedia\(\s*"\(prefers-color-scheme:\s*dark\)"\s*\)\.matches\s*\?\s*"dark"\s*:\s*"light"/
      )
    end
  end

  describe "onSystemChange — auto-mode tracking" do
    let(:on_system_body) do
      # Field-style arrow handler — match `onSystemChange = () => { ... }`.
      controller_source[/onSystemChange\s*=\s*\(\s*\)\s*=>\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as a field-style arrow handler (bound this)" do
      # Arrow + class-field means `this` is bound automatically — the
      # same function reference can be add/removeEventListener'd
      # without a `.bind(this)` dance.
      expect(controller_source).to match(/onSystemChange\s*=\s*\(\s*\)\s*=>\s*\{/)
    end

    it "checks localStorage for an explicit preference before reacting" do
      expect(on_system_body).to match(/localStorage\.getItem\(\s*"pito-theme"\s*\)/)
    end

    it "only re-applies the theme when no explicit preference is stored" do
      # Auto mode (absent localStorage entry) tracks the OS; an
      # explicit `light` / `dark` choice freezes the theme. The
      # `if (!pref)` guard enforces that contract.
      expect(on_system_body).to match(/if\s*\(\s*!pref\s*\)/)
      expect(on_system_body).to include("this.applyTheme()"),
        "expected the auto-mode branch to re-apply the theme"
    end
  end

  describe "Phase 29 — server PATCH removed" do
    it "does not call fetch() or otherwise PATCH the theme to the server" do
      # The pre-Phase-29 implementation PATCHed `/settings/theme` to
      # persist the choice server-side. That endpoint was removed
      # along with the Settings → ui/ux pane — the controller is now
      # localStorage-only. Any fetch() or XHR is regression.
      #
      # Strip block + line comments first so the explanatory header
      # comment (which mentions /settings/theme historically) doesn't
      # trip the guard. We only care about live code.
      code_only = controller_source
        .gsub(%r{/\*.*?\*/}m, "")
        .gsub(%r{//.*$}, "")

      expect(code_only).not_to match(/fetch\s*\(/),
        "theme controller must not call fetch() — Phase 29 dropped " \
        "server-side theme persistence (localStorage only)"
      expect(code_only).not_to match(/XMLHttpRequest/),
        "theme controller must not use XMLHttpRequest — Phase 29 " \
        "dropped server-side theme persistence (localStorage only)"
      expect(code_only).not_to include("/settings/theme"),
        "theme controller code must not reference /settings/theme — " \
        "Phase 29 removed the endpoint (comments documenting the " \
        "removal are fine; live code references are regression)"
    end
  end
end
