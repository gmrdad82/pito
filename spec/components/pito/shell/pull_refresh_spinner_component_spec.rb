# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::PullRefreshSpinnerComponent, type: :component do
  before { allow(Current).to receive(:session).and_return(double("Session")) }

  it "renders nothing for an anonymous session (chrome stays off anonymous layouts)" do
    allow(Current).to receive(:session).and_return(nil)
    expect(render_inline(described_class.new).to_html.strip).to be_empty
  end

  it "renders an inert <template> with the stable id pito--pull-refresh clones" do
    node = render_inline(described_class.new)
    expect(node.css("template#pito-pull-refresh-spinner")).not_to be_empty
  end

  it "carries the spinner tile with its clone marker, hidden from assistive tech" do
    inner = render_inline(described_class.new).css("template#pito-pull-refresh-spinner").first.inner_html
    expect(inner).to include("pito-pull-spinner")
    expect(inner).to include("data-pull-refresh-spinner")
    expect(inner).to include(%(aria-hidden="true"))
  end

  it "inlines the Lucide refresh arrow stroked with the theme-var gradient (no external fetch)" do
    inner = render_inline(described_class.new).css("template#pito-pull-refresh-spinner").first.inner_html
    expect(inner).to include("<svg")
    expect(inner).to include(%(stroke="url(#pito-pull-grad)"))
    expect(inner).to include("var(--accent-purple)", "var(--brand-pito)")
    expect(inner).not_to include("href", "src=")
  end
end
