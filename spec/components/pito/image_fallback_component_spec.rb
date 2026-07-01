# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ImageFallbackComponent, type: :component do
  def render_fallback(**opts)
    render_inline(described_class.new(**{ shape: :rect, sync_command: "sync vid #1" }.merge(opts)))
  end

  it "renders the muted fallback box with the no-image copy" do
    node = render_fallback
    box  = node.at_css("div.pito-image-fallback")
    expect(box).to be_present
    expect(box.text).to include("No image.")
  end

  it "renders a sync affordance line" do
    node = render_fallback
    expect(node.at_css(".pito-image-fallback__sync").text.strip).to eq("sync")
  end

  it "makes the WHOLE box a click-to-sync affordance (prefill + real Enter)" do
    box = render_fallback(sync_command: "sync game #3").at_css(".pito-image-fallback")
    expect(box["data-controller"]).to eq("pito--chat-prefill")
    expect(box["data-action"]).to eq("click->pito--chat-prefill#fill")
    expect(box["data-pito--chat-prefill-text-value"]).to eq("sync game #3")
    expect(box["data-pito--chat-prefill-submit-value"]).to eq("true")
  end

  it "adds the circle modifier for :circle shape" do
    expect(render_fallback(shape: :circle).at_css(".pito-image-fallback.pito-image-fallback--circle")).to be_present
  end

  it "does not add the circle modifier for :rect shape" do
    expect(render_fallback(shape: :rect).at_css(".pito-image-fallback--circle")).to be_nil
  end

  it "falls back to a rectangle for an unknown shape" do
    expect(render_fallback(shape: :hexagon).at_css(".pito-image-fallback--circle")).to be_nil
  end

  it "applies the host sizing class passed as extra_class" do
    expect(render_fallback(extra_class: "pito-channel-item__avatar").at_css(".pito-image-fallback.pito-channel-item__avatar")).to be_present
  end

  it "is keyboard-reachable (role=button, tabindex=0)" do
    box = render_fallback.at_css(".pito-image-fallback")
    expect(box["role"]).to eq("button")
    expect(box["tabindex"]).to eq("0")
  end
end
