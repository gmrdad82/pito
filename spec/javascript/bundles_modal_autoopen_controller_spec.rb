require "rails_helper"

# 2026-05-18 — Static-source regression guard for the bundles modal
# auto-open controller. Mounted on the `<dialog id="bundles-modal">`
# shell ONLY when the modal partial is rendered with a `bundle:`
# local (i.e. from the `BundlesController#create` Turbo Stream
# response). On `connect()` the controller calls `showModal()` so
# the user lands directly inside the freshly-created bundle without
# an extra click. Steady-state renders omit this controller.
RSpec.describe "bundles_modal_autoopen_controller.js" do
  let(:controller_source) do
    File.read(Rails.root.join("app/javascript/controllers/bundles_modal_autoopen_controller.js"))
  end

  let(:source_without_comments) do
    controller_source.gsub(%r{//[^\n]*}, "")
  end

  it "extends the Stimulus Controller base class" do
    expect(controller_source).to include('import { Controller } from "@hotwired/stimulus"')
    expect(controller_source).to match(/export default class extends Controller/)
  end

  it "implements connect() as the only behavior surface" do
    expect(controller_source).to match(/^\s*connect\(\)\s*\{/)
  end

  it "guards on showModal being a function (browser support)" do
    expect(controller_source).to match(/typeof this\.element\.showModal\s*!==\s*"function"/)
  end

  it "guards against re-opening an already-open dialog" do
    expect(controller_source).to match(/if \(this\.element\.open\) return/)
  end

  it "invokes showModal on the element to promote the dialog" do
    expect(controller_source).to include("this.element.showModal()")
  end

  it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
    expect(source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
  end
end
