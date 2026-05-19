require "rails_helper"

# 2026-05-18 — Static-source regression guard for the bundles modal
# trigger controller. The trigger is mounted on each `.bundle-tile`
# anchor; on click it preventDefaults, repoints the layout-level
# Turbo Frame, swaps the modal title, and rewrites the per-bundle
# PATCH URL onto the inline-title-edit controller plus the
# per-bundle delete-confirm dialog id onto the `[-]` button before
# `showModal()`. These assertions lock the contractual surface;
# implementation details (timing of querySelector, exact attribute
# names beyond the documented ones) are intentionally left fluid.
RSpec.describe "bundles_modal_trigger_controller.js" do
  let(:controller_source) do
    File.read(Rails.root.join("app/javascript/controllers/bundles_modal_trigger_controller.js"))
  end

  # Strip single-line `// …` comments so the "no JS alert/confirm/prompt"
  # assertion below ignores the controller's own documentation lines that
  # reference the rule itself.
  let(:source_without_comments) do
    controller_source.gsub(%r{//[^\n]*}, "")
  end

  it "extends the Stimulus Controller base class" do
    expect(controller_source).to include('import { Controller } from "@hotwired/stimulus"')
    expect(controller_source).to match(/export default class extends Controller/)
  end

  it "declares the documented Stimulus values (url, title, updateUrl, deleteConfirmId, dialogId, frameId, titleId)" do
    %w[url title updateUrl deleteConfirmId dialogId frameId titleId].each do |key|
      expect(controller_source).to match(/^\s*#{Regexp.escape(key)}:\s/),
        "expected `#{key}:` to appear as a Stimulus value declaration"
    end
  end

  it "defaults the dialog id to bundles-modal" do
    expect(controller_source).to match(/dialogId:\s*\{\s*type:\s*String,\s*default:\s*"bundles-modal"\s*\}/)
  end

  it "defaults the frame id to bundles_modal_frame" do
    expect(controller_source).to match(/frameId:\s*\{\s*type:\s*String,\s*default:\s*"bundles_modal_frame"\s*\}/)
  end

  it "defines an `open` action method" do
    expect(controller_source).to match(/^\s*open\(event\)\s*\{/)
  end

  it "preventDefaults the click so the fallback href does not navigate" do
    expect(controller_source).to include("event.preventDefault()")
  end

  it "resolves dialog + frame nodes via getElementById on the configured value ids" do
    expect(controller_source).to include("document.getElementById(this.dialogIdValue)")
    expect(controller_source).to include("document.getElementById(this.frameIdValue)")
  end

  it "writes the per-bundle src onto the Turbo Frame when urlValue is present" do
    expect(controller_source).to match(/if \(this\.urlValue\)\s*\{[^}]*frame\.setAttribute\("src", this\.urlValue\)/m)
  end

  it "swaps the modal title via the `title` Stimulus target inside the dialog" do
    expect(controller_source).to include('[data-bundles-modal-target="title"]')
    expect(controller_source).to match(/titleEl\.textContent\s*=\s*this\.titleValue/)
  end

  it "writes the per-bundle PATCH URL onto the inline-title-edit urlHolder target" do
    expect(controller_source).to include('[data-bundles-modal-target="urlHolder"]')
    expect(controller_source).to include('setAttribute("data-inline-title-edit-url-value", this.updateUrlValue)')
  end

  it "writes the per-bundle delete-confirm dialog id onto the deleteButton target" do
    expect(controller_source).to include('[data-bundles-modal-target="deleteButton"]')
    expect(controller_source).to include('setAttribute("data-modal-trigger-target-id-value", this.deleteConfirmIdValue)')
  end

  it "calls showModal only when the dialog is closed and supports the API" do
    expect(controller_source).to match(/typeof dialog\.showModal === "function"[^{]*&&\s*!dialog\.open[^{]*\{\s*dialog\.showModal\(\)/m)
  end

  it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
    expect(source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
  end
end
