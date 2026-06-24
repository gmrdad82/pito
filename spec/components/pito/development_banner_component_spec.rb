# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::DevelopmentBannerComponent do
  subject(:node) { render_inline(described_class.new) }

  it "renders the DEVELOPMENT label from Pito::Copy (not hardcoded)" do
    expect(node.text.strip).to eq(Pito::Copy.render("pito.copy.development.banner"))
  end

  it "renders 'DEVELOPMENT'" do
    expect(node.text).to include("DEVELOPMENT")
  end

  it "is a fixed, full-viewport-width red banner pinned to the bottom" do
    # w-screen (not right-0) so it spans past html's stable scrollbar gutter to the edge.
    div = node.css("div").first
    classes = div["class"]
    expect(classes).to include("fixed", "bottom-0", "left-0", "w-screen", "bg-red")
  end

  it "uses the default foreground for readable contrast on red" do
    expect(node.css("div").first["class"]).to include("text-fg")
  end

  it "does not intercept clicks on the UI below it" do
    expect(node.css("div").first["class"]).to include("pointer-events-none")
  end
end
