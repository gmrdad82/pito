# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::HandleComponent do
  it "renders #handle in purple" do
    node = render_inline(described_class.new("alpha-1322"))
    expect(node.text).to eq("#alpha-1322")
    expect(node.css("span.text-purple")).to be_present
  end

  it "renders data-pito-handle attribute for client handle collection" do
    node = render_inline(described_class.new("alpha-1322"))
    span = node.css("span[data-pito-handle]").first
    expect(span).to be_present
    expect(span["data-pito-handle"]).to eq("alpha-1322")
  end

  it "renders nothing when handle is blank" do
    node = render_inline(described_class.new(""))
    expect(node.text).to be_blank
  end

  it "renders nothing when handle is nil" do
    node = render_inline(described_class.new(nil))
    expect(node.text).to be_blank
  end
end
