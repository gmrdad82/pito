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

  it "carries the shrug, the hint marker, and a resolved dictionary line" do
    inner = render_inline(described_class.new).css("template#pito-pull-refresh-hint").first.inner_html
    expect(inner).to include("(ツ)")
    expect(inner).to include("data-pull-refresh-hint")
    expect(inner).to include("pito-pull-hint__text")
    hints = I18n.t("pito.copy.pull_refresh.hints")
    expect(hints.any? { |h| inner.include?(ERB::Util.html_escape(h)) }).to be(true)
  end
end
