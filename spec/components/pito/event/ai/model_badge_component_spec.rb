# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::Ai::ModelBadgeComponent, type: :component do
  it "leads with the centralized AI sparkle (Pito::Ai::BadgeComponent) beside the model name" do
    node = render_inline(described_class.new(model: "deepseek-v4-flash-free"))

    badge = node.css(".pito-ai-model-badge")
    expect(badge).not_to be_empty
    expect(badge.text).to include("deepseek-v4-flash-free")
    # the shared shimmer-masked sparkle, not a bespoke inline SVG
    expect(badge.first.css("span.pito-ai-badge")).not_to be_empty
    expect(badge.first.inner_html).not_to include("<svg")
  end

  it "renders nothing without a model (messages that predate the stamp)" do
    expect(render_inline(described_class.new(model: nil)).to_html.strip).to be_empty
    expect(render_inline(described_class.new(model: "")).to_html.strip).to be_empty
  end

  it "renders the answer's cost as the house coin + two-decimal amount + currency code" do
    node = render_inline(described_class.new(
      model: "deepseek-v4-flash-free", cost_amount: 0.0123, cost_currency: "USD"
    ))

    expect(node.css("img.pito-coin")).not_to be_empty
    expect(node.text).to include("$0.01") # symbol attaches — no space
    expect(node.text).not_to include("USD")
  end

  it "falls back to code-with-space for symbol-less currencies and shows free as $0.00" do
    chf = render_inline(described_class.new(model: "m", cost_amount: 0.5, cost_currency: "CHF"))
    expect(chf.text).to include("0.50 CHF")

    free = render_inline(described_class.new(model: "m-free", cost_amount: 0.0, cost_currency: "USD"))
    expect(free.text).to include("$0.00")
  end

  it "renders no cost segment when the answer carries no pricing stamp" do
    node = render_inline(described_class.new(model: "m-1"))
    expect(node.css("img.pito-coin")).to be_empty
  end
end
