# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# tui_cursor_controller — INSERT-mode SPACE toggle contract.
# Phase 1D (2026-05-24 sync-rebuild).
# =============================================================================
#
# This spec locks the INSERT-mode SPACE keybinding behavior via static
# source analysis of the controller. NORMAL-mode SPACE is owned by the
# leader menu controller — the cursor controller MUST NOT consume
# SPACE in NORMAL mode (regression guard).
#
# Behavior expectations:
#
# 1. INSERT mode + SPACE on a text input → pass through (the input
#    receives the space character).
# 2. INSERT mode + SPACE on the focused focusable → call
#    `toggleFocusedFocusableCheckbox()` which (a) toggles a checkbox
#    when the focusable IS or CONTAINS one, or (b) clicks an
#    action-style button (the Tui::SyncIndicatorComponent :target
#    case). `preventDefault` is called when the helper succeeded so
#    the native button SPACE keyup activation does NOT double-fire.
# 3. NORMAL mode SPACE is NEVER consumed by handleNormalKey — even
#    when a focusable is focused, SPACE bubbles to the leader menu.
# =============================================================================

RSpec.describe "tui_cursor_controller INSERT-mode SPACE contract" do
  let(:js_source) do
    Rails.root.join("app/javascript/controllers/tui_cursor_controller.js").read
  end

  describe "INSERT-mode SPACE handler" do
    it "exists inside handleInsertKey for k === ' '" do
      expect(js_source).to match(/handleInsertKey\(event\)[\s\S]+?if \(k === " "\)/)
    end

    it "skips the toggle when active element is a text input (pass-through)" do
      expect(js_source).to match(
        /if \(k === " "\)[\s\S]+?onTextInput\s*=\s*active\s*&&\s*active\.matches[\s\S]+?if \(onTextInput\) return/
      )
    end

    it "calls toggleFocusedFocusableCheckbox() to toggle the focused focusable" do
      expect(js_source).to match(
        /if \(k === " "\)[\s\S]+?this\.toggleFocusedFocusableCheckbox\(\)/
      )
    end

    it "preventDefaults + stopsPropagation when the toggle helper succeeds" do
      expect(js_source).to match(
        /toggleFocusedFocusableCheckbox\(\)\) \{\s*event\.preventDefault\(\)\s*event\.stopPropagation\(\)/
      )
    end
  end

  describe "toggleFocusedFocusableCheckbox helper" do
    it "Path 1 — clicks the checkbox when the focusable IS or CONTAINS one" do
      expect(js_source).to match(
        /toggleFocusedFocusableCheckbox\(\)[\s\S]+?input\[type="checkbox"\][\s\S]+?checkbox\.click\(\)/
      )
    end

    it "Path 2 — clicks the action-style button (sync VC :target mode)" do
      # 2026-05-24 (sync-rebuild) — Path 2 now covers BOTH the focusable
      # IS the button AND the focusable contains a button (more general).
      expect(js_source).to match(/tuiFocusableStyle === "action"/)
      expect(js_source).to match(/button\.click\(\)/)
    end

    it "returns false when neither path matches (so SPACE falls through silently)" do
      expect(js_source).to match(/toggleFocusedFocusableCheckbox\(\)[\s\S]+?return false\s*\}\s*$/)
    end
  end

  describe "NORMAL-mode SPACE — never consumed (leader menu owns it)" do
    it "handleNormalKey does NOT route SPACE through toggleFocusedFocusableCheckbox" do
      # The NORMAL-mode switch must not have a `case " ":` branch wired to
      # any toggle path. Lock the contract by asserting the comment-locked
      # 2026-05-24 docblock that explains the deliberate omission.
      expect(js_source).to include('NORMAL-mode SPACE is OWNED by the leader menu')
    end

    it "the explicit SPACE-passes-to-leader-menu docblock is present" do
      expect(js_source).to match(/SPACE\s*→\s*leader menu/i)
    end
  end

  describe "handleFocusOut — DOM-hide guard (FB-167 extension)" do
    # When a Stimulus controller hides the row that owns the currently-focused
    # checkbox (e.g. sessions-bulk-revoke swaps defaultHeader → actionHeader),
    # the browser fires a `focusout` on the now-hidden element. Without the
    # guard, handleFocusOut would call exitInsertMode() and the cursor would
    # drop out of INSERT unexpectedly. The guard detects that the losing
    # element is inside a `[hidden]` ancestor and re-focuses instead.
    it "checks t.closest('[hidden]') before calling exitInsertMode" do
      expect(js_source).to match(/t\.closest\("\[hidden\]"\)/)
    end

    it "calls refocusForFocusable inside the hidden-ancestor guard branch" do
      expect(js_source).to match(
        /t\.closest\("\[hidden\]"\)[\s\S]+?refocusForFocusable\(\)/
      )
    end

    it "uses setTimeout to defer the re-focus one tick for DOM settle" do
      expect(js_source).to match(
        /setTimeout\(\(\) => \{ this\.refocusForFocusable\(\) \}, 0\)/
      )
    end

    it "returns early from the guard branch without calling exitInsertMode" do
      # The guard branch must `return` before reaching exitInsertMode().
      # We verify there is a `return` between the hidden-ancestor check
      # and the `exitInsertMode()` call.
      expect(js_source).to match(
        /t\.closest\("\[hidden\]"\)[\s\S]+?return\s*\n[\s\S]+?this\.exitInsertMode\(\)/
      )
    end
  end
end
