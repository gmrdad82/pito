# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Ai::BadgeComponent, type: :component do
  it "renders the shimmer-masked sparkle span, hidden from the accessibility tree" do
    node = render_inline(described_class.new(ai: true))
    badge = node.css("span.pito-ai-badge").first
    expect(badge).to be_present
    expect(badge["aria-hidden"]).to eq("true")
    expect(badge.text).to eq("")
  end

  it "renders nothing when the ai gate is false" do
    expect(render_inline(described_class.new(ai: false)).to_html.strip).to eq("")
  end
end
