# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::PullRefreshHintComponent, type: :component do
  before { allow(Current).to receive(:session).and_return(double("Session")) }

  it "renders nothing for an anonymous session (chrome stays off anonymous layouts)" do
    allow(Current).to receive(:session).and_return(nil)
    expect(render_inline(described_class.new).to_html.strip).to be_empty
  end

  it "renders an inert <template> with the stable id pito--pull-refresh clones" do
    node = render_inline(described_class.new)
    expect(node.css("template#pito-pull-refresh-hint")).not_to be_empty
  end

  it "carries a dictionary kaomoji, the hint marker, and a resolved dictionary line" do
    inner = render_inline(described_class.new).css("template#pito-pull-refresh-hint").first.inner_html
    expect(inner).to include("data-pull-refresh-hint")
    expect(inner).to include("pito-pull-hint__text")
    hints = I18n.t("pito.copy.pull_refresh.hints")
    expect(hints.any? { |h| inner.include?(ERB::Util.html_escape(h)) }).to be(true)
  end

  # G93: both halves sample their OWN 50-variant dictionary independently —
  # 2500 combos, repetition stays rare.
  it "samples the kaomoji from the 50-glyph dictionary" do
    glyphs = I18n.t("pito.copy.pull_refresh.glyphs")
    expect(glyphs.length).to eq(50)

    inner = render_inline(described_class.new).css(".pito-pull-hint__shrug").first
    expect(glyphs).to include(CGI.unescapeHTML(inner.inner_html))
  end

  # #2: the reveal is a 5-row ASCII block — three filled arrows, the shrug+copy
  # row, and the filled circle that arms the reload.
  it "renders three arrow rows and a circle reload row" do
    inner = render_inline(described_class.new).css("template#pito-pull-refresh-hint").first.inner_html
    expect(inner.scan("pito-pull-hint__arrow").size).to eq(3)
    expect(inner).to include("pito-pull-hint__circle")
    expect(inner).to include("▲")
    expect(inner).to include("●")
  end
end
