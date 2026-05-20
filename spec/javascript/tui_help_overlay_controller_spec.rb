require "rails_helper"

# Beta 4 — Phase F1. Static-source structural lock for the
# `tui-help-overlay` Stimulus controller
# (`app/javascript/controllers/tui_help_overlay_controller.js`).
#
# Mirrors the `tui_status_bar_controller_spec.rb` discipline:
# rack_test has no JS engine, so the actual showModal() / close()
# round-trip can't be exercised at runtime here. What we CAN lock is
# the source text — lifecycle wiring, the form-input gate, the `?`
# toggle key, the `Escape` close key, and the modifier gates that
# prevent Ctrl/Meta-`?` from firing the overlay.
#
# Drift in any of these (renamed handler, dropped teardown, missed
# modifier check) silently breaks the help surface on every
# authenticated page.
RSpec.describe "tui_help_overlay_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/tui_help_overlay_controller.js")
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

  describe "connect() — listener attach" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "binds the handler before attaching it (for symmetric removal)" do
      expect(connect_body).to match(/this\.boundHandler\s*=\s*this\.handleKey\.bind\(\s*this\s*\)/)
    end

    it "attaches the keydown listener at document level" do
      expect(connect_body).to match(/document\.addEventListener\(\s*"keydown",\s*this\.boundHandler\s*\)/)
    end
  end

  describe "disconnect() — clean teardown" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "removes the document-level keydown listener" do
      expect(disconnect_body).to match(/document\.removeEventListener\(\s*"keydown",\s*this\.boundHandler\s*\)/)
    end
  end

  describe "handleKey() — gating" do
    let(:handle_body) do
      controller_source[/handleKey\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "bails when the event target is a form input / textarea / select / [contenteditable]" do
      # Typing `?` into a search field must not pop the overlay. The
      # gate must list every form-input surface explicitly — drift
      # here is how `?` ends up stealing keystrokes from the
      # everywhere modal.
      expect(handle_body).to match(/matches\(\s*"input,\s*textarea,\s*select,\s*\[contenteditable\]"\s*\)/)
    end

    it "bails on Ctrl / Meta / Alt modifiers (Shift allowed because `?` needs Shift on most layouts)" do
      expect(handle_body).to match(/event\.ctrlKey\s*\|\|\s*event\.metaKey\s*\|\|\s*event\.altKey/)
    end
  end

  describe "handleKey() — `?` toggles, `Escape` closes" do
    let(:handle_body) do
      controller_source[/handleKey\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "calls toggle() when key is `?`" do
      expect(handle_body).to match(/event\.key\s*===\s*"\?"/)
      expect(handle_body).to include("this.toggle()")
    end

    it "calls preventDefault() after handling `?`" do
      expect(handle_body).to include("event.preventDefault()")
    end

    it "closes on `Escape` but only when the dialog is already open" do
      # The Escape branch is guarded by `this.element.open` so an
      # unrelated Escape (e.g., closing a different overlay layered
      # above) doesn't try to .close() a non-open <dialog>.
      expect(handle_body).to match(
        /event\.key\s*===\s*"Escape"\s*&&\s*this\.element\.open/
      )
      expect(handle_body).to include("this.close()")
    end
  end

  describe "toggle() / open() / close() — dialog API binding" do
    let(:toggle_body) do
      controller_source[/toggle\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end
    let(:open_body) do
      controller_source[/open\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end
    let(:close_body) do
      controller_source[/close\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines toggle(), open(), and close() methods" do
      expect(controller_source).to match(/toggle\s*\(\s*\)\s*\{/)
      expect(controller_source).to match(/open\s*\(\s*\)\s*\{/)
      expect(controller_source).to match(/close\s*\(\s*\)\s*\{/)
    end

    it "toggle() branches on `this.element.open`" do
      expect(toggle_body).to match(/this\.element\.open/)
      expect(toggle_body).to include("this.close()")
      expect(toggle_body).to include("this.open()")
    end

    it "open() calls the native `showModal()` (lands the overlay in the top layer)" do
      # `showModal()` is mandatory rather than `show()` so the
      # overlay sits above any pre-existing `<dialog>` on the page
      # (e.g., the leader menu, a confirm overlay).
      expect(open_body).to match(/this\.element\.showModal\(\)/)
    end

    it "close() calls the native `close()` method on the dialog" do
      expect(close_body).to match(/this\.element\.close\(\)/)
    end
  end
end
