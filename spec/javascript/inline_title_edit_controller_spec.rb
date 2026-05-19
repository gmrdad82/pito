require "rails_helper"

# 2026-05-18 — Static-source regression guard for the inline title
# edit controller used by the `/games` bundles modal heading. The
# controller flips between a static display and an inline input +
# `[update][cancel]` pair, PATCHes the bundle name as JSON via
# `fetch`, and on success swaps back inline + propagates the rename
# to the matching `#bundle-tile-<id>` caption in the /games shelf.
#
# Contract under test:
#   - Stimulus targets: display, editing, input.
#   - Stimulus values: url.
#   - Action methods: edit, cancel, save, handleKey, swapToDisplay,
#     reset.
#   - Validation guards: non-blank, race guard, urlValue required.
#   - JSON PATCH with CSRF token + Accept + Content-Type headers.
#   - 422 errors → toast-error; 200 → text update + tile rename +
#     toast-notice; network failure → toast-error.
#   - Escape stopPropagation so the surrounding <dialog> does NOT
#     also close when the user dismisses the inline edit.
#   - `reset()` cross-controller hook used by `bundles-modal-reset`.
RSpec.describe "inline_title_edit_controller.js" do
  let(:controller_source) do
    File.read(Rails.root.join("app/javascript/controllers/inline_title_edit_controller.js"))
  end

  let(:source_without_comments) do
    controller_source.gsub(%r{//[^\n]*}, "")
  end

  it "extends the Stimulus Controller base class" do
    expect(controller_source).to include('import { Controller } from "@hotwired/stimulus"')
    expect(controller_source).to match(/export default class extends Controller/)
  end

  it "declares display, editing, and input targets" do
    expect(controller_source).to match(/static targets = \[\s*"display",\s*"editing",\s*"input"\s*\]/)
  end

  it "declares a url value" do
    expect(controller_source).to match(/static values = \{\s*url:\s*String\s*\}/)
  end

  it "defines edit, cancel, save, handleKey, swapToDisplay, and reset methods" do
    %w[edit cancel save handleKey swapToDisplay reset].each do |method|
      expect(controller_source).to match(/^\s*#{Regexp.escape(method)}\(/),
        "expected `#{method}` to be defined"
    end
  end

  it "edit() seeds the input from the title text node and reveals the editing block" do
    edit_block = controller_source[/^\s*edit\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(edit_block).to include("this.inputTarget.value = this.titleTextEl().textContent.trim()")
    expect(edit_block).to include("this.displayTarget.hidden = true")
    expect(edit_block).to include("this.editingTarget.hidden = false")
    expect(edit_block).to include("requestAnimationFrame(")
    expect(edit_block).to include("this.inputTarget.focus()")
    expect(edit_block).to include("this.inputTarget.select()")
  end

  it "cancel() reverts the input value to the current title text and swaps back to display" do
    cancel_block = controller_source[/^\s*cancel\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(cancel_block).to include("this.inputTarget.value = this.titleTextEl().textContent.trim()")
    expect(cancel_block).to include("this.swapToDisplay()")
  end

  it "save() short-circuits when the trimmed input is blank" do
    expect(controller_source).to match(/if \(newName\.length === 0\) return/)
  end

  it "save() short-circuits when a submission is already in flight" do
    expect(controller_source).to match(/if \(this\.submitting\) return/)
  end

  it "save() short-circuits when no urlValue has been bound yet" do
    expect(controller_source).to match(/if \(!this\.urlValue\) return/)
  end

  it "save() reads the CSRF token from the meta tag" do
    expect(controller_source).to include('document.querySelector(\'meta[name="csrf-token"]\')')
  end

  it "save() PATCHes the bundle URL with JSON body { bundle: { name } }" do
    expect(controller_source).to match(/fetch\(this\.urlValue,\s*\{/)
    expect(controller_source).to match(/method:\s*"PATCH"/)
    expect(controller_source).to include('"Accept": "application/json"')
    expect(controller_source).to include('"Content-Type": "application/json"')
    expect(controller_source).to include('"X-CSRF-Token"')
    expect(controller_source).to include("JSON.stringify({ bundle: { name: newName } })")
  end

  it "save() flashes a toast-error on non-ok responses" do
    expect(controller_source).to include('this._flashToast(message, "toast-error")')
  end

  it "save() updates the title text inline and swaps back to display on success" do
    expect(controller_source).to match(/this\.titleTextEl\(\)\.textContent\s*=\s*newName/)
    expect(controller_source).to match(/this\.swapToDisplay\(\)/)
  end

  it "save() propagates the rename to the matching #bundle-tile-<id> caption in the /games shelf" do
    expect(controller_source).to include("document.getElementById(`bundle-tile-${payload.id}`)")
    expect(controller_source).to include("tile.querySelector(\".bundle-tile-name\")")
    expect(controller_source).to match(/captionEl\.textContent\s*=\s*newName/)
    expect(controller_source).to include('tile.setAttribute("title", newName)')
    expect(controller_source).to include('tile.setAttribute("data-bundles-modal-trigger-title-value", newName)')
  end

  it "save() flashes a toast-notice on success" do
    expect(controller_source).to include('this._flashToast("bundle updated.", "toast-notice")')
  end

  it "save() clears the submitting flag in a finally block" do
    expect(controller_source).to match(/\.finally\(\(\)\s*=>\s*\{[^}]*this\.submitting\s*=\s*false[^}]*\}\)/m)
  end

  it "save() falls back to a toast-error on network-level failure (fetch rejection)" do
    expect(controller_source).to match(/\.catch\(\(err\)\s*=>\s*\{[^}]*this\._flashToast\("could not update bundle\.",\s*"toast-error"\)/m)
  end

  it "_flashToast appends a toast into the layout's .toast-container with the toast Stimulus controller" do
    flash_block = controller_source[/^\s*_flashToast\([^)]*\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(flash_block).to include('document.querySelector(".toast-container")')
    expect(flash_block).to include('toast.setAttribute("data-controller", "toast")')
    expect(flash_block).to include('toast.setAttribute("role", "status")')
  end

  it "handleKey() submits on Enter and cancels on Escape" do
    key_block = controller_source[/^\s*handleKey\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(key_block).to include('event.key === "Enter"')
    expect(key_block).to include("this.save(event)")
    expect(key_block).to include('event.key === "Escape"')
    expect(key_block).to include("this.cancel(event)")
  end

  it "handleKey() stops propagation on Escape so the surrounding <dialog> does not also close" do
    key_block = controller_source[/^\s*handleKey\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(key_block).to include("event.stopPropagation()")
  end

  it "swapToDisplay() reveals the display target and hides the editing target" do
    swap_block = controller_source[/^\s*swapToDisplay\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(swap_block).to include("this.displayTarget.hidden = false")
    expect(swap_block).to include("this.editingTarget.hidden = true")
  end

  it "reset() clears the input, urlValue, submitting flag, and returns to display state" do
    reset_block = controller_source[/^\s*reset\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(reset_block).to include("this.inputTarget.value = \"\"")
    expect(reset_block).to match(/this\.urlValue\s*=\s*""/)
    expect(reset_block).to match(/this\.submitting\s*=\s*false/)
    expect(reset_block).to include("this.swapToDisplay()")
  end

  it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
    expect(source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
  end
end
