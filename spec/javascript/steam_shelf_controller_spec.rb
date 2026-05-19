require "rails_helper"

# 2026-05-18 — Static-source structural lock for the `steam-shelf`
# Stimulus controller
# (`app/javascript/controllers/steam_shelf_controller.js`).
#
# This controller turns vertical mouse-wheel motion into horizontal
# scroll on /games shelf rows (and adds drag-to-scroll). Rack_test
# can't fire a wheel event, so the spec locks the source-level
# contract that drives the recent Brave wheel-debt hotfix:
#
#   - The wheel listener is registered passive=false so
#     `event.preventDefault()` actually takes effect.
#   - The handler ONLY calls preventDefault when the shelf can
#     absorb the scroll in the requested direction (the hotfix —
#     pages were stuck because Brave kept feeding wheel-debt to a
#     handler that always intercepted).
#   - Vertical wheel becomes `scrollLeft += deltaY`; horizontal-
#     dominant trackpad gestures are ignored.
#
# Drift in any of these silently breaks shelf scrolling — visible
# but not throwing. This spec is the early-warning trip wire.
RSpec.describe "steam_shelf_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/steam_shelf_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "declares `row` as a Stimulus target" do
      expect(controller_source).to match(
        /static\s+targets\s*=\s*\[\s*"row"\s*\]/
      )
    end
  end

  describe "connect() — wires wheel + mousedown listeners on the row" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "resolves the row from the Stimulus target (with element fallback)" do
      # `hasRowTarget ? this.rowTarget : this.element` lets the
      # controller mount on either the scrollable row directly or a
      # wrapping element that names the row via data-steam-shelf-target.
      expect(connect_body).to match(
        /this\.hasRowTarget\s*\?\s*this\.rowTarget\s*:\s*this\.element/
      )
    end

    it "binds the handler refs to the instance so removeEventListener works" do
      # The teardown in disconnect() depends on referencing the SAME
      # function pointer that addEventListener received. Without
      # explicit .bind(this) caching, the listeners leak on Turbo morphs.
      expect(connect_body).to match(/this\.onWheel\s*=\s*this\.onWheel\.bind\(\s*this\s*\)/)
      expect(connect_body).to match(/this\.onMouseDown\s*=\s*this\.onMouseDown\.bind\(\s*this\s*\)/)
      expect(connect_body).to match(/this\.onMouseMove\s*=\s*this\.onMouseMove\.bind\(\s*this\s*\)/)
      expect(connect_body).to match(/this\.onMouseUp\s*=\s*this\.onMouseUp\.bind\(\s*this\s*\)/)
    end

    it "registers the wheel listener with passive:false (so preventDefault works)" do
      # passive:true defaults silently swallow preventDefault — the
      # browser warns in dev but ships the wheel through. passive:false
      # is REQUIRED for the vertical-to-horizontal translate to land.
      expect(connect_body).to match(
        /addEventListener\(\s*"wheel"\s*,\s*this\.onWheel\s*,\s*\{\s*passive:\s*false\s*\}\s*\)/
      )
    end

    it "registers the mousedown listener on the row (drag-to-scroll entry)" do
      expect(connect_body).to match(
        /addEventListener\(\s*"mousedown"\s*,\s*this\.onMouseDown\s*\)/
      )
    end
  end

  describe "disconnect() — removes every listener wired in connect()" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "removes the row-level wheel listener with the SAME handler ref" do
      expect(disconnect_body).to match(
        /this\.row\.removeEventListener\(\s*"wheel"\s*,\s*this\.onWheel\s*\)/
      )
    end

    it "removes the row-level mousedown listener with the SAME handler ref" do
      expect(disconnect_body).to match(
        /this\.row\.removeEventListener\(\s*"mousedown"\s*,\s*this\.onMouseDown\s*\)/
      )
    end

    it "removes the document-level mousemove + mouseup drag listeners" do
      # The drag handlers attach to `document` (not the row) so a drag
      # that escapes the row's bounding box still ends cleanly. Both
      # must be removed on teardown or the next Turbo render leaks them.
      expect(disconnect_body).to match(
        /document\.removeEventListener\(\s*"mousemove"\s*,\s*this\.onMouseMove\s*\)/
      )
      expect(disconnect_body).to match(
        /document\.removeEventListener\(\s*"mouseup"\s*,\s*this\.onMouseUp\s*\)/
      )
    end
  end

  describe "onWheel() — vertical-to-horizontal translate with scroll-can-absorb gate" do
    let(:on_wheel_body) do
      controller_source[/onWheel\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines onWheel(event)" do
      expect(controller_source).to match(/onWheel\s*\(\s*event\s*\)\s*\{/)
    end

    it "ignores horizontal-dominant wheel events (trackpad horizontal gestures)" do
      # `Math.abs(event.deltaY) <= Math.abs(event.deltaX)` — when the
      # trackpad is already scrolling horizontally we don't want to
      # double-handle. Early return.
      expect(on_wheel_body).to match(
        /if\s*\(\s*Math\.abs\(\s*event\.deltaY\s*\)\s*<=\s*Math\.abs\(\s*event\.deltaX\s*\)\s*\)\s*return/
      )
    end

    it "computes whether the shelf can scroll further right" do
      # The +/- 1px tolerance handles browsers that report fractional
      # scroll positions; without it, an at-end shelf could read as
      # "still scrollable" and re-intercept the wheel.
      expect(on_wheel_body).to match(
        /this\.row\.scrollLeft\s*<\s*this\.row\.scrollWidth\s*-\s*this\.row\.clientWidth\s*-\s*1/
      )
    end

    it "computes whether the shelf can scroll further left" do
      expect(on_wheel_body).to match(/this\.row\.scrollLeft\s*>\s*0/)
    end

    it "derives the requested direction from event.deltaY sign" do
      expect(on_wheel_body).to match(/wantsRight\s*=\s*event\.deltaY\s*>\s*0/)
      expect(on_wheel_body).to match(/wantsLeft\s*=\s*event\.deltaY\s*<\s*0/)
    end

    it "bails (no preventDefault) when the shelf cannot absorb in the requested direction" do
      # THE Brave-wheel-debt hotfix. A shelf that's scrolled all the
      # way right MUST let the wheel pass through to the page so the
      # user can keep scrolling vertically. Previously the handler
      # always intercepted, leaving Brave's wheel-debt accumulator
      # spinning forever on a stuck page.
      expect(on_wheel_body).to match(
        /if\s*\(\s*\(wantsRight\s*&&\s*!canScrollRight\)\s*\|\|\s*\(wantsLeft\s*&&\s*!canScrollLeft\)\s*\)\s*return/
      )
    end

    it "calls event.preventDefault() ONLY after the can-scroll gate passes" do
      # Order matters — the preventDefault call must sit AFTER the
      # bail. Source slice from the can-absorb gate to end-of-method.
      gate_to_end = on_wheel_body[/canScrollLeft[\s\S]*?\}\s*\z/m].to_s
      expect(gate_to_end).to include("event.preventDefault()"),
        "expected preventDefault to live BELOW the can-scroll gate so " \
        "the page scrolls naturally when the shelf has nowhere to go"
    end

    it "translates the vertical wheel delta into horizontal scrollLeft" do
      expect(on_wheel_body).to match(
        /this\.row\.scrollLeft\s*\+=\s*event\.deltaY/
      )
    end
  end

  describe "drag-to-scroll — onMouseDown/Move/Up" do
    it "onMouseDown only engages on the primary button (event.button === 0)" do
      body = controller_source[/onMouseDown\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/if\s*\(\s*event\.button\s*!==\s*0\s*\)\s*return/),
        "right/middle clicks must not start a drag-scroll"
    end

    it "onMouseDown caches startX (relative to row) and startScroll" do
      body = controller_source[/onMouseDown\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/this\.startX\s*=\s*event\.pageX\s*-\s*this\.row\.offsetLeft/)
      expect(body).to match(/this\.startScroll\s*=\s*this\.row\.scrollLeft/)
    end

    it "onMouseDown registers document-level mousemove + mouseup for the drag" do
      body = controller_source[/onMouseDown\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/document\.addEventListener\(\s*"mousemove"\s*,\s*this\.onMouseMove\s*\)/)
      expect(body).to match(/document\.addEventListener\(\s*"mouseup"\s*,\s*this\.onMouseUp\s*\)/)
    end

    it "onMouseMove no-ops unless a drag is in progress" do
      body = controller_source[/onMouseMove\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/if\s*\(\s*!this\.dragging\s*\)\s*return/)
    end

    it "onMouseMove translates pointer displacement into reverse scrollLeft" do
      # The shelf scrolls in the opposite direction the pointer moved
      # — that's the standard "grab and pull the page" feel. Delta is
      # subtracted from startScroll.
      body = controller_source[/onMouseMove\s*\(\s*event\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/this\.row\.scrollLeft\s*=\s*this\.startScroll\s*-\s*delta/)
    end

    it "onMouseUp clears the dragging flag and tears down the document-level listeners" do
      body = controller_source[/onMouseUp\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/this\.dragging\s*=\s*false/)
      expect(body).to match(/document\.removeEventListener\(\s*"mousemove"\s*,\s*this\.onMouseMove\s*\)/)
      expect(body).to match(/document\.removeEventListener\(\s*"mouseup"\s*,\s*this\.onMouseUp\s*\)/)
    end
  end

  describe "Hard rules — no JS alert / confirm / prompt" do
    it "does not call window.alert / confirm / prompt or set data-turbo-confirm" do
      # Per project CLAUDE.md hard rule. This controller is a pure UI
      # affordance — there's no scenario where a confirm prompt belongs.
      #
      # Strip block + line comments first so the controller's own
      # explanatory header ("NO confirm() / alert() / prompt() — pure
      # UI affordance") doesn't trip the guard. We only care about
      # live code.
      code_only = controller_source
        .gsub(%r{/\*.*?\*/}m, "")
        .gsub(%r{//.*$}, "")

      expect(code_only).not_to match(/\bwindow\.(?:alert|confirm|prompt)\s*\(/),
        "no window.alert/confirm/prompt — destructive flows use the " \
        "action-screen framework (see CLAUDE.md hard rules)"
      expect(code_only).not_to match(/(?<![a-zA-Z_$.])(?:alert|confirm|prompt)\s*\(/),
        "no bare alert/confirm/prompt calls — destructive flows use " \
        "the action-screen framework (see CLAUDE.md hard rules)"
      expect(code_only).not_to include("data-turbo-confirm"),
        "no data-turbo-confirm — same hard rule"
    end
  end
end
