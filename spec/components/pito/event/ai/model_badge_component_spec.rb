# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::Ai::ModelBadgeComponent, type: :component do
  it "renders the sparkles glyph stroked with the AI gradient beside the model name" do
    node = render_inline(described_class.new(model: "deepseek-v4-flash-free"))

    badge = node.css(".pito-ai-model-badge")
    expect(badge).not_to be_empty
    expect(badge.text).to include("deepseek-v4-flash-free")

    html = badge.first.inner_html
    expect(html).to include("<svg")
    expect(html).to include(%(stroke="url(#pito-ai-badge-grad)"))
    expect(html).to include("var(--accent-purple)", "var(--brand-pito)")
    expect(html).not_to include("href", "src=")
  end

  it "renders nothing without a model (messages that predate the stamp)" do
    expect(render_inline(described_class.new(model: nil)).to_html.strip).to be_empty
    expect(render_inline(described_class.new(model: "")).to_html.strip).to be_empty
  end
end
