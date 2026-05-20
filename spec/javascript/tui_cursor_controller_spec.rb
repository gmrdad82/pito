require "rails_helper"

# Beta 4 — Phase F1. Static-source structural lock for the
# `tui-cursor` Stimulus controller
# (`app/javascript/controllers/tui_cursor_controller.js`).
#
# Mirrors the `tui_status_bar_controller_spec.rb` discipline:
# rack_test has no JS engine, so the actual keydown round-trip can't
# be exercised at runtime here. What we CAN lock is the source text —
# target declarations, lifecycle wiring, the form-input + dialog
# gates, the TAB / Shift-TAB / Ctrl-h/j/k/l key map, the
# `data-tui-cursor-focused="yes"` marker, and the scrollIntoView call
# on focus change.
#
# Drift in any of these (renamed target, dropped teardown, missed
# modifier check, missing dialog guard) silently breaks panel
# navigation on every multi-pane page.
RSpec.describe "tui_cursor_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/tui_cursor_controller.js")
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
    it "declares `panel` as a Stimulus target" do
      expect(controller_source).to match(/"panel"/)
    end

    it "declares the targets via `static targets = [...]`" do
      expect(controller_source).to match(/static\s+targets\s*=\s*\[/)
    end
  end

  describe "connect() — listener attach + initial focus" do
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

    it "seeds the focused index to 0" do
      expect(connect_body).to match(/this\.focusedIndex\s*=\s*0/)
    end

    it "applies the initial focus on connect" do
      expect(connect_body).to match(/this\.applyFocus\(\s*\)/)
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
      # Mirrors the gate on every other global keydown controller —
      # typing TAB / Ctrl-h while inside a search field must still
      # behave naturally.
      expect(handle_body).to match(/matches\(\s*"input,\s*textarea,\s*select,\s*\[contenteditable\]"\s*\)/)
    end

    it "bails when a `dialog[open]` element exists in the document" do
      # The leader menu, command palette, help overlay etc. are
      # `<dialog>` elements. While any of them is open, panel-nav
      # keystrokes must NOT cycle the underlying surface.
      expect(handle_body).to match(/document\.querySelector\(\s*"dialog\[open\]"\s*\)/)
    end
  end

  describe "handleKey() — TAB / Shift-TAB" do
    let(:handle_body) do
      controller_source[/handleKey\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "advances on plain TAB (no shift, no ctrl, no meta)" do
      expect(handle_body).to match(
        /event\.key\s*===\s*"Tab"\s*&&\s*!event\.shiftKey\s*&&\s*!event\.ctrlKey\s*&&\s*!event\.metaKey/
      )
      expect(handle_body).to include("this.next()")
    end

    it "rewinds on Shift+TAB (shift, no ctrl, no meta)" do
      expect(handle_body).to match(
        /event\.key\s*===\s*"Tab"\s*&&\s*event\.shiftKey\s*&&\s*!event\.ctrlKey\s*&&\s*!event\.metaKey/
      )
      expect(handle_body).to include("this.previous()")
    end
  end

  describe "handleKey() — Ctrl-h/j/k/l direction chord" do
    let(:handle_body) do
      controller_source[/handleKey\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "only triggers when ctrlKey is set and meta / shift are not" do
      expect(handle_body).to match(
        /event\.ctrlKey\s*&&\s*!event\.metaKey\s*&&\s*!event\.shiftKey/
      )
    end

    {
      "h" => "previous",
      "l" => "next",
      "j" => "next",
      "k" => "previous"
    }.each do |key, direction|
      it "maps Ctrl+#{key} to #{direction}()" do
        # The case statement order matters less than the case ->
        # action pairing — every case must dispatch the correct
        # direction.
        case_chunk = handle_body[/case\s*"#{key}":\s*\n[^\n]*/m].to_s
        expect(case_chunk).to include("this.#{direction}()"),
          "expected Ctrl+#{key} to call this.#{direction}() inside its case branch"
      end
    end

    it "calls preventDefault + stopPropagation when a key was handled" do
      expect(handle_body).to include("event.preventDefault()")
      expect(handle_body).to include("event.stopPropagation()")
    end
  end

  describe "next() / previous() — index advance with wrap" do
    let(:next_body) do
      controller_source[/next\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end
    let(:previous_body) do
      controller_source[/previous\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "bails when there are no panel targets" do
      expect(next_body).to match(/this\.panelTargets\.length\s*===\s*0/)
      expect(previous_body).to match(/this\.panelTargets\.length\s*===\s*0/)
    end

    it "advances next() with `(idx + 1) % length` wrap" do
      expect(next_body).to match(
        /this\.focusedIndex\s*=\s*\(\s*this\.focusedIndex\s*\+\s*1\s*\)\s*%\s*this\.panelTargets\.length/
      )
    end

    it "rewinds previous() with `(idx - 1 + length) % length` wrap (no negative idx)" do
      expect(previous_body).to match(
        /this\.focusedIndex\s*=\s*\(\s*this\.focusedIndex\s*-\s*1\s*\+\s*this\.panelTargets\.length\s*\)\s*%\s*this\.panelTargets\.length/
      )
    end

    it "calls applyFocus() after the index change in both directions" do
      expect(next_body).to include("this.applyFocus()")
      expect(previous_body).to include("this.applyFocus()")
    end
  end

  describe "applyFocus() — DOM marker + scroll" do
    let(:apply_body) do
      controller_source[/applyFocus\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "iterates over panelTargets via forEach((el, idx) => ...)" do
      expect(apply_body).to match(/this\.panelTargets\.forEach\(\s*\(\s*el,\s*idx\s*\)\s*=>/)
    end

    it "sets `data-tui-cursor-focused=\"yes\"` on the focused panel" do
      # The dataset assignment camel-cases the attr name. The
      # rendered attribute is `data-tui-cursor-focused="yes"`; the JS
      # writes `el.dataset.tuiCursorFocused = "yes"`.
      expect(apply_body).to match(/el\.dataset\.tuiCursorFocused\s*=\s*"yes"/)
    end

    it "removes the focused marker from non-focused panels (via `delete`)" do
      expect(apply_body).to match(/delete\s+el\.dataset\.tuiCursorFocused/)
    end

    it "calls scrollIntoView on the focused panel" do
      expect(apply_body).to match(/el\.scrollIntoView\(/)
    end

    it "uses block: 'nearest' for the scroll behavior (no full-page jumps)" do
      expect(apply_body).to match(/block:\s*"nearest"/)
    end
  end
end
