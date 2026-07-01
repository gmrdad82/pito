# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Share::LinkComponent, type: :component do
  let(:url) { "https://dev.pitomd.com/share/abc-123-def" }

  subject(:node) { render_inline(described_class.new(url:)) }

  it "renders the URL as a clickable action-class link opening in a new tab" do
    a = node.at_css("a.pito-action-shimmer")
    expect(a).to be_present
    expect(a["href"]).to eq(url)
    expect(a["target"]).to eq("_blank")
    expect(a["rel"]).to eq("noopener")
    expect(a.text).to eq(url)
  end

  it "renders the shared copy widget (pito--clipboard) with the full URL as the text to copy" do
    wrap = node.at_css(".pito-copy[data-controller='pito--clipboard']")
    expect(wrap).to be_present
    expect(wrap["data-pito--clipboard-text-value"]).to eq(url)
  end

  it "renders a copy-ICON button (not text) that triggers the clipboard controller" do
    btn = node.at_css("button.pito-copy__btn[data-action='click->pito--clipboard#copy']")
    expect(btn).to be_present
    expect(btn.at_css("svg.pito-icon")).to be_present   # the lucide copy icon, not the word "Copy"
  end

  it "places the copy widget INLINE right after the URL link" do
    html = node.to_html
    expect(html.index("</a>")).to be < html.index("pito-copy")
  end

  it "has a separate (empty) Copied! feedback target" do
    fb = node.at_css("[data-pito--clipboard-target='feedback']")
    expect(fb).to be_present
    expect(fb.text.strip).to eq("")
  end

  it "keeps the inline timestamp slot on the first line" do
    expect(node.at_css("[data-pito-ts-slot]")).to be_present
  end
end
