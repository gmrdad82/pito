require "rails_helper"

# 2026-05-18 — Static-source regression guard for the shared
# omnisearch modal controller. The omnisearch family currently
# contains a single controller (`omnisearch_modal_controller.js`);
# `global_search_modal_controller.js` is a sibling but is a
# different mount surface (the layout-rendered global `/` keypress
# modal — out of scope for this spec).
#
# Contract under test:
#   - Stimulus targets: input.
#   - Stimulus values: url, debounce (default 250), minChars
#     (default 1), frameId.
#   - open / close / clickOutside / keydown ESC behavior.
#   - Debounced `search` that fires the configured Turbo Frame
#     swap; Enter bypasses the debounce and the min-chars gate
#     is respected for non-Enter inputs.
RSpec.describe "omnisearch_modal_controller.js" do
  let(:controller_source) do
    File.read(Rails.root.join("app/javascript/controllers/omnisearch_modal_controller.js"))
  end

  let(:source_without_comments) do
    controller_source.gsub(%r{//[^\n]*}, "")
  end

  it "extends the Stimulus Controller base class" do
    expect(controller_source).to include('import { Controller } from "@hotwired/stimulus"')
    expect(controller_source).to match(/export default class extends Controller/)
  end

  it "declares the `input` target" do
    expect(controller_source).to match(/static targets = \[\s*"input"\s*\]/)
  end

  it "declares url, debounce (default 250), minChars (default 1), and frameId values" do
    expect(controller_source).to match(/^\s*url:\s*String/)
    expect(controller_source).to match(/^\s*debounce:\s*\{\s*type:\s*Number,\s*default:\s*250\s*\}/)
    expect(controller_source).to match(/^\s*minChars:\s*\{\s*type:\s*Number,\s*default:\s*1\s*\}/)
    expect(controller_source).to match(/^\s*frameId:\s*String/)
  end

  it "initializes the debounce timer in connect()" do
    connect_block = controller_source[/connect\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(connect_block).to match(/this\._timer\s*=\s*null/)
  end

  it "clears the pending timer in disconnect()" do
    disconnect_block = controller_source[/disconnect\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(disconnect_block).to include("clearTimeout(this._timer)")
  end

  it "defines open(), close(), clickOutside(), keydown(), and search() action methods" do
    %w[open close clickOutside keydown search].each do |method|
      expect(controller_source).to match(/^\s*#{Regexp.escape(method)}\(/),
        "expected `#{method}` to be defined as an action method"
    end
  end

  it "opens the dialog via showModal when not already open" do
    expect(controller_source).to match(/typeof this\.element\.showModal === "function"[^{]*&&\s*!this\.element\.open[^{]*\{\s*this\.element\.showModal\(\)/m)
  end

  it "focuses the input after open (defers via setTimeout 0) without pre-selecting" do
    # 2026-05-18 — open() defers focus via setTimeout 0 so the <dialog>
    # promotion finishes handing focus around before we grab it. The
    # previous behavior also called `.select()` on the input; user
    # feedback (and the _reset() pattern) made every open start from a
    # blank input, so there is nothing to select. Lock both halves: the
    # setTimeout 0 focus IS wired AND `.select()` is NOT called inside
    # the deferred callback.
    expect(controller_source).to match(/setTimeout\(\s*\(\)\s*=>\s*\{[^}]*this\.inputTarget\.focus\(\)[^}]*\},\s*0\)/m)
    open_block = controller_source[/^\s*open\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(open_block).not_to include("this.inputTarget.select()")
  end

  it "calls _reset() inside open() so each open starts from a clean input" do
    open_block = controller_source[/^\s*open\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(open_block).to include("this._reset()")
  end

  it "calls _reset() inside close() so the next open starts clean even if dismiss bypasses open()" do
    close_block = controller_source[/^\s*close\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(close_block).to include("this._reset()")
  end

  it "calls _reset() inside clickOutside() after closing the dialog" do
    co_block = controller_source[/^\s*clickOutside\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(co_block).to include("this._reset()")
  end

  it "calls _reset() inside keydown() so Escape leaves no stale state" do
    keydown_block = controller_source[/^\s*keydown\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(keydown_block).to include("this._reset()")
  end

  it "defines _reset() that clears the input value, cancels the pending timer, and wipes the frame" do
    reset_block = controller_source[/^\s*_reset\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(reset_block).not_to be_empty, "expected `_reset()` to be defined"
    # Cancels any in-flight debounced query.
    expect(reset_block).to include("clearTimeout(this._timer)")
    expect(reset_block).to match(/this\._timer\s*=\s*null/)
    # Clears the input so the next open starts empty.
    expect(reset_block).to match(/this\.inputTarget\.value\s*=\s*""/)
    # Wipes the results Turbo Frame so stale results don't flash.
    expect(reset_block).to include("document.getElementById(frameId)")
    expect(reset_block).to include('frame.removeAttribute("src")')
    expect(reset_block).to include("frame.replaceChildren()")
  end

  it "closes the dialog on the close action when the dialog is open" do
    close_block = controller_source[/^\s*close\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(close_block).to match(/this\.element\.close\(\)/)
    expect(close_block).to include("this.element.open")
  end

  it "closes on click-outside when the click target is the dialog backdrop itself" do
    co_block = controller_source[/^\s*clickOutside\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(co_block).to match(/event\.target === this\.element/)
    expect(co_block).to include("this.element.close()")
  end

  it "treats Escape as a close" do
    keydown_block = controller_source[/^\s*keydown\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(keydown_block).to include('event.key === "Escape"')
    expect(keydown_block).to include("this.element.close()")
  end

  it "respects the min-chars gate for non-Enter inputs" do
    expect(controller_source).to match(/q\.length < this\.minCharsValue/)
  end

  it "bypasses the debounce when Enter is pressed and fires immediately" do
    search_block = controller_source[/^\s*search\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(search_block).to match(/event\.key === "Enter"/)
    expect(search_block).to match(/this\._fire\(q\)/)
  end

  it "schedules the debounced fire via setTimeout using debounceValue" do
    expect(controller_source).to match(/setTimeout\(\(\)\s*=>\s*this\._fire\(q\),\s*this\.debounceValue\)/)
  end

  it "_fire builds a URL using urlValue, sets the `q` search param, and swaps the configured Turbo Frame src" do
    fire_block = controller_source[/^\s*_fire\(q\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(fire_block).to include("new URL(this.urlValue, window.location.origin)")
    expect(fire_block).to include('url.searchParams.set("q", q)')
    expect(fire_block).to include("document.getElementById(frameId)")
    expect(fire_block).to match(/frame\.src\s*=\s*url\.toString\(\)/)
  end

  it "no-ops _fire when frameId is missing" do
    fire_block = controller_source[/^\s*_fire\(q\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(fire_block).to match(/if \(!frameId\) return/)
  end

  it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
    expect(source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
  end
end
