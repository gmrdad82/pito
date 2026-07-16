# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::DevelopmentBannerComponent do
  subject(:node) { render_inline(described_class.new) }

  it "renders the DEVELOPMENT wordmark (environment marker, not Pito::Copy)" do
    # The fps meter moved to the toggleable top-left chip (owner 2026-07-15,
    # Pito::FpsOverlayComponent) — the ribbon is the wordmark again.
    expect(node.text).to include("DEVELOPMENT")
    expect(node.css("#pito-fx-fps")).to be_empty
  end

  it "is a fixed, full-width red ribbon raised off the screen edge (owner: near mini-status)" do
    div = node.css("div").first
    classes = div["class"]
    expect(classes).to include("fixed", "bottom-1", "left-0", "right-0", "bg-red")
  end

  it "uses the default foreground for readable contrast on red" do
    expect(node.css("div").first["class"]).to include("text-fg")
  end

  it "does not intercept clicks on the UI below it" do
    expect(node.css("div").first["class"]).to include("pointer-events-none")
  end
end
