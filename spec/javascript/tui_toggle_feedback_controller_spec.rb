require "rails_helper"

# Beta 4 — Phase F3-B-TOGGLE-FEEDBACK. Static-source structural lock
# for the `tui-toggle-feedback` Stimulus controller
# (`app/javascript/controllers/tui_toggle_feedback_controller.js`).
#
# Mirrors the `tui_indicator_controller_spec.rb` discipline: rack_test
# has no JS engine, so the actual `change` / `turbo:submit-end`
# round-trip can't be exercised at runtime here. What we CAN lock is
# the source text — target declarations, lifecycle hooks, event
# listener attach + detach symmetry, and the glyph / spinner
# visibility flip.
#
# Drift in any of these (renamed target, dropped teardown, missed
# event name) silently breaks the braille feedback on the
# notification toggles and the user sees no in-flight signal between
# click and save.
RSpec.describe "tui_toggle_feedback_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/tui_toggle_feedback_controller.js")
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

  describe "Stimulus targets" do
    # Every target name in
    # `app/views/settings/_notifications_pane.html.erb` must appear
    # here. Renaming a target on either side without updating both
    # silently no-ops the spinner.
    %w[checkbox glyph spinner].each do |target_name|
      it "declares `#{target_name}` as a Stimulus target" do
        expect(controller_source).to match(/"#{Regexp.escape(target_name)}"/),
          "expected `#{target_name}` in the static targets array"
      end
    end

    it "declares the targets via `static targets = [...]`" do
      expect(controller_source).to match(/static\s+targets\s*=\s*\[/)
    end
  end

  describe "connect() — listener attach" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "guards checkbox listener attach behind `hasCheckboxTarget`" do
      expect(connect_body).to match(/if\s*\(\s*this\.hasCheckboxTarget\s*\)/)
    end

    it "binds `change` on the checkbox target to startSpinner()" do
      expect(connect_body).to match(/addEventListener\(\s*"change"/)
      expect(connect_body).to match(/this\.startSpinner\(\)/)
    end

    it "resolves the enclosing form via `element.closest('form')`" do
      expect(connect_body).to match(/this\.element\.closest\(\s*"form"\s*\)/)
    end

    it "binds `turbo:submit-end` on the form to endSpinner()" do
      expect(connect_body).to match(/addEventListener\(\s*"turbo:submit-end"/)
      expect(connect_body).to match(/this\.endSpinner/)
    end
  end

  describe "disconnect() — clean teardown" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "removes the `change` listener from the checkbox target" do
      expect(disconnect_body).to match(/removeEventListener\(\s*"change"/)
    end

    it "removes the `turbo:submit-end` listener from the form" do
      expect(disconnect_body).to match(/removeEventListener\(\s*"turbo:submit-end"/)
    end

    it "nulls cached listener refs so a re-mount starts clean" do
      expect(disconnect_body).to match(/this\.onChange\s*=\s*null/)
      expect(disconnect_body).to match(/this\.onSubmitEnd\s*=\s*null/)
    end
  end

  describe "startSpinner() — glyph hide, spinner reveal" do
    let(:start_body) do
      controller_source[/startSpinner\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a startSpinner() method" do
      expect(controller_source).to match(/startSpinner\s*\(\s*\)\s*\{/)
    end

    it "hides the glyph target by setting its `hidden` attribute (removes it from inline flow)" do
      # 2026-05-20 — switched from `style.visibility = "hidden"` to
      # `hidden = true` so the glyph leaves the inline flow entirely.
      # The bracketed spinner (`[<tui-indicator>]`) then occupies the
      # 3ch slot via natural flow — no margin tricks, no overlay, no
      # text shift while the spinner is showing.
      expect(start_body).to match(/this\.glyphTarget\.hidden\s*=\s*true/)
    end

    it "unhides the spinner target by clearing its `hidden` attribute" do
      expect(start_body).to match(/this\.spinnerTarget\.hidden\s*=\s*false/)
    end
  end

  describe "endSpinner() — restore glyph, hide spinner" do
    # The body extraction looks for the `endSpinner(...)` opening line
    # and consumes up to the matching `  }` at column 2 with NO method
    # boundary marker (`\n\n` blank line OR `}` at column 0 closing
    # the class) in between. Anchoring on the trailing `}\n}` /
    # `}\n\n` shape keeps us inside the method.
    let(:end_body) do
      # Grab from `endSpinner(` to the next blank line or end of file.
      match = controller_source.match(/endSpinner\s*\([^)]*\)\s*\{(.*?)^\s{2}\}/m)
      match ? match[1].to_s : ""
    end

    it "defines an endSpinner() method" do
      expect(controller_source).to match(/endSpinner\s*\(/)
    end

    it "re-hides the spinner target" do
      expect(end_body).to match(/this\.spinnerTarget\.hidden\s*=\s*true/)
    end

    it "restores the glyph target by clearing its `hidden` attribute" do
      expect(end_body).to match(/this\.glyphTarget\.hidden\s*=\s*false/)
    end
  end
end
