require "rails_helper"

# 2026-05-18 — Static-source regression guard for the bundles modal
# teardown controller. The dialog is layout-positioned (one per page)
# and the trigger swaps per-bundle content in on every open; without
# a reset on close, the previous bundle's inline-edit state, title
# text, and Turbo Frame contents leak into the next open. This spec
# locks the documented teardown surface: native `close` event hook,
# inline-title-edit `reset()` cross-controller call, title clear,
# Turbo Frame `src` removal + children replaceChildren wipe.
RSpec.describe "bundles_modal_reset_controller.js" do
  let(:controller_source) do
    File.read(Rails.root.join("app/javascript/controllers/bundles_modal_reset_controller.js"))
  end

  let(:source_without_comments) do
    controller_source.gsub(%r{//[^\n]*}, "")
  end

  it "extends the Stimulus Controller base class" do
    expect(controller_source).to include('import { Controller } from "@hotwired/stimulus"')
    expect(controller_source).to match(/export default class extends Controller/)
  end

  it "binds the native dialog close event in connect()" do
    connect_block = controller_source[/connect\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(connect_block).to include('this.element.addEventListener("close"')
  end

  it "unbinds the same listener in disconnect()" do
    disconnect_block = controller_source[/disconnect\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
    expect(disconnect_block).to include('this.element.removeEventListener("close"')
  end

  it "defines a `handleClose` method as the close-event callback" do
    expect(controller_source).to match(/^\s*handleClose\(\)\s*\{/)
  end

  it "looks up the inline-title-edit row inside the dialog" do
    expect(controller_source).to include('[data-controller~="inline-title-edit"]')
  end

  it "calls the inline-title-edit controller's `reset()` via the Stimulus application registry" do
    expect(controller_source).to include("getControllerForElementAndIdentifier")
    expect(controller_source).to match(/editCtrl\.reset\(\)/)
  end

  it "belt-and-braces clears the inline-title-edit url-value attribute" do
    expect(controller_source).to include('setAttribute("data-inline-title-edit-url-value", "")')
  end

  it "clears the modal title text element" do
    expect(controller_source).to include('[data-bundles-modal-target="title"]')
    expect(controller_source).to match(/titleEl\.textContent\s*=\s*""/)
  end

  it "removes the Turbo Frame `src` and wipes its children via replaceChildren()" do
    expect(controller_source).to include('[data-bundles-modal-target="frame"]')
    expect(controller_source).to include('frame.removeAttribute("src")')
    expect(controller_source).to include("frame.replaceChildren()")
  end

  it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
    expect(source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
  end
end
