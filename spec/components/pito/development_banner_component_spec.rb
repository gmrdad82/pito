# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::DevelopmentBannerComponent do
  subject(:node) { render_inline(described_class.new) }

  it "renders the DEVELOPMENT label from Pito::Copy (not hardcoded)" do
    # The ribbon IS the meter now (owner 2026-07-13): no wordmark copy, the
    # red bar marks the environment, the meter is the content.
    expect(node.css("#pito-fx-fps[data-controller='pito--fx-fps']").text).to eq("-- fps")
    expect(node.text).not_to include("DEVELOPMENT")
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
