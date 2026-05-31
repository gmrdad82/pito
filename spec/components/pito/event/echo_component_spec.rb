# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::EchoComponent do
  it "renders the echoed command text" do
    node = render_inline(described_class.new(payload: { text: "list videos" }))

    expect(node.to_html).to include("list videos")
    expect(node.css("span.text-fg").text).to include("list videos")
  end

  it "coerces a missing text payload to an empty string (no crash)" do
    node = render_inline(described_class.new(payload: {}))

    expect(node.css("span.text-fg")).not_to be_empty
    expect(node.css("span.text-fg").text.strip).to eq("")
  end

  it "wraps the echo in a Segment carrying the orange accent" do
    node = render_inline(described_class.new(payload: { text: "hello" }))

    # The Segment bar is rendered with the accent color as its background;
    # assert the orange accent token is present rather than an exact rule
    # so this survives the P10 data-accent restyle.
    expect(node.to_html).to include("var(--accent-orange)")
  end
end
