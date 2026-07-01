# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::CopyButtonComponent, type: :component do
  subject(:node) { render_inline(described_class.new(text: "copy me", aria_label: "Copy the thing")) }

  it "is a self-contained pito--clipboard widget carrying the text to copy" do
    wrap = node.at_css(".pito-copy[data-controller='pito--clipboard']")
    expect(wrap).to be_present
    expect(wrap["data-pito--clipboard-text-value"]).to eq("copy me")
  end

  it "renders the lucide copy ICON button (action-shimmer class), not the word Copy" do
    btn = node.at_css("button.pito-copy__btn[data-action='click->pito--clipboard#copy']")
    expect(btn).to be_present
    expect(btn["aria-label"]).to eq("Copy the thing")
    expect(btn.at_css("svg.pito-icon")).to be_present
    expect(btn.text).not_to include("Copy")
  end

  it "has a separate empty Copied! feedback target" do
    fb = node.at_css(".pito-copy__feedback[data-pito--clipboard-target='feedback']")
    expect(fb).to be_present
    expect(fb.text.strip).to eq("")
  end
end
