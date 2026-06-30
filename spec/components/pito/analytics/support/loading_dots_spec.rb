# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Support::LoadingDots, type: :component do
  it "renders the small comet markup with all 8 dots" do
    node = render_inline(described_class.new)
    expect(node.css(".pito-loading-dots")).to be_present
    expect(node.css(".pito-loading-dots .dot").size).to eq(described_class::DOTS)
  end

  it "applies a stagger delay bucket class" do
    node = render_inline(described_class.new(seed: "views"))
    klass = node.css(".pito-loading-dots").first["class"]
    expect(klass).to match(/pito-loading-dots--d[0-4]/)
  end

  it "maps the same seed to the same bucket (stable)" do
    a = render_inline(described_class.new(seed: "likes")).css(".pito-loading-dots").first["class"]
    b = render_inline(described_class.new(seed: "likes")).css(".pito-loading-dots").first["class"]
    expect(a).to eq(b)
  end

  it "is decorative (aria-hidden)" do
    node = render_inline(described_class.new(seed: 3))
    expect(node.css(".pito-loading-dots").first["aria-hidden"]).to eq("true")
  end
end
